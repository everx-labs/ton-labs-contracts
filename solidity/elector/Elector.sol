/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;
pragma ignoreIntOverflow;
pragma AbiHeader time;
import "IConfig.sol";
import "IElector.sol";
import "IValidator.sol";
import "Common.sol";

// Config parameters used in the contract:
//  0  Configuration smart-contract address
//  1  Elector smart-contract address
// 13  Complaint prices
// 15  Election parameters
// 16  Validator count
// 17  Validator stake parameters
// 34  Current validator set
// 36  Next validator set

contract Elector is IElector {

    uint256 constant SLASHER_ADDRESS = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 constant PRECISION = 1e18;

    struct Elect {
        uint32 elect_at;
        uint32 elect_close;
        uint128 min_stake;
        uint128 total_stake;
        mapping(uint256 => Member) members;
        bool failed;
        bool finished;
    }

    struct Member {
        uint128 stake;
        uint32 time;
        uint32 max_factor;
        uint256 addr;
        uint256 adnl_addr;
    }

    struct PastElection {
        uint32 unfreeze_at;
        uint32 stake_held;
        uint256 vset_hash;
        mapping(uint256 => Frozen) frozen_dict;
        uint128 total_stake;
        uint128 bonuses;
        mapping(uint256 => ComplaintStatus) complaints;
    }

    struct Frozen {
        uint256 addr;
        uint64 weight;
        uint128 stake;
        bool banned;
    }

    struct ComplaintStatus {
        uint8 tag; // = 0x2d
        TvmCell complaint;
        mapping(uint16 => uint32) voters;
        uint256 vset_id;
        int64 weight_remaining;
    }

    bool m_election_open;
    Elect m_cur_elect;
    mapping(uint256 => uint128) m_credits;
    mapping(uint32 => PastElection) m_past_elections;
    uint128 m_grams;
    uint32 m_active_id;
    uint256 m_active_hash;

    constructor() public {
        m_election_open = false;
    }

    function get_complaint_prices() internal pure returns (uint128, uint128, uint128) {
        (TvmCell info, bool f) = tvm.rawConfigParam(13);
        if (!f)
            return (1 << 36, 1, 512);
        TvmSlice s = info.toSlice();
        uint8 tag = s.loadUnsigned(8);
        require(tag == 0x1a, 9);
        uint128 deposit = s.loadTons();
        uint128 bit = s.loadTons();
        uint128 cell = s.loadTons();
        return (deposit, bit, cell);
    }

    function get_validator_conf() internal pure inline returns (uint32, uint32, uint32, uint32) {
        (uint32 elect_for, uint32 elect_begin_before,
          uint32 elect_end_before, uint32 stake_held, /* bool */) = tvm.configParam(15);
        return (elect_for, elect_begin_before, elect_end_before, stake_held);
    }

    function get_current_vset() internal pure returns (TvmCell, uint64, mapping(uint16 => TvmSlice)) {
        (TvmCell info, /* bool */) = tvm.rawConfigParam(34);
        Common.ValidatorSet vset = info.toSlice().decode(Common.ValidatorSet);
        require(vset.tag == 0x12, 40);
        return (info, vset.total_weight, vset.vdict);
    }

    function send_message_back(address addr, uint32 ans_tag, uint64 query_id,
                               uint32 body, uint128 amount, uint8 mode) internal pure {
        TvmBuilder b;
        b.storeUnsigned(0x18, 6);
        b.store(addr);
        b.storeTons(amount);
        b.storeUnsigned(0, 1 + 4 + 4 + 64 + 32 + 1 + 1);
        b.store(ans_tag);
        b.store(query_id);
        b.storeUnsigned(body, 32);
        tvm.sendrawmsg(b.toCell(), mode);
    }

    function return_stake(uint64 query_id, uint32 reason) internal pure {
        IValidator(msg.sender).return_stake{value: 0, flag: 64}(query_id, reason);
    }

    function send_confirmation(uint64 query_id, uint32 comment) internal pure {
        IValidator(msg.sender).confirmation{value: 1 ton, flag: 2}(query_id, comment);
    }

    function send_validator_set_to_config(uint256 config_addr, TvmCell vset,
                                          uint64 query_id) internal pure inline {
        address addr = address.makeAddrStd(-1, config_addr);
        IConfig(addr).set_next_validator_set{value: (1 << 30), flag: 1}(query_id, vset);
    }

    function credit_to(uint256 addr, uint128 amount) internal inline {
        m_credits[addr] += amount;
        //emit CreditToEvent(addr, amount);
    }

    function process_new_stake(uint64 query_id, uint256 validator_pubkey,
                               uint32 stake_at, uint32 max_factor,
                               uint256 adnl_addr, bytes signature)
            override public functionID(0x4e73744b) onlyInternalMessage {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (!m_election_open || src_wc != -1) {
            // no elections active, or source is not in masterchain
            // bounce message
            return return_stake(query_id, 0);
        }
        TvmBuilder data;
        data.store(uint32(0x654c5074), stake_at, max_factor, src_addr, adnl_addr);
        TvmBuilder sign;
        sign.store(signature);
        if (!tvm.checkSign(data.toSlice(), sign.toSlice().loadRefAsSlice(), validator_pubkey)) {
            // incorrect signature, return stake
            return return_stake(query_id, 1);
        }
        if (max_factor < 0x10000) {
            // factor must be >= 1. = 65536/65536
            return return_stake(query_id, 6);
        }
        uint128 total_stake = m_cur_elect.total_stake;
        // deduct GR$1 for sending confirmation
        uint256 msg_value = msg.value - 1 ton;
        if ((msg_value << 12) < total_stake) {
            // stake smaller than 1/4096 of the total accumulated stakes, return
            return return_stake(query_id, 2);
        }
        // (provisionally) increase total stake
        total_stake += uint128(msg_value);
        if (stake_at != m_cur_elect.elect_at) {
            // stake for some other elections, return
            return return_stake(query_id, 3);
        }
        if (m_cur_elect.finished) {
            // elections already finished, return stake
            return return_stake(query_id, 0);
        }
        optional(Member) m = m_cur_elect.members.fetch(validator_pubkey);
        bool found = false;
        if (m.hasValue()) {
            // log("merging stakes");
            Member mem = m.get();
            // entry found, merge stakes
            msg_value += mem.stake;
            found = (src_addr != mem.addr);
        }
        if (found) {
            // can make stakes for a public key from one address only
            return return_stake(query_id, 4);
        }
        if (msg_value < m_cur_elect.min_stake) {
            // stake too small, return it
            return return_stake(query_id, 5);
        }
        (, uint128 max_stake, , , ) = tvm.configParam(17);
        if (msg_value > max_stake) {
            // stake exceeds max_stake config parameter, return it
            return return_stake(query_id, 7);
        }
        require(msg_value != 0, 44);
        tvm.accept();
        // store stake in the dictionary
        m_cur_elect.members[validator_pubkey] =
            Member(uint128(msg_value), now, max_factor, src_addr, adnl_addr);
        m_cur_elect.failed = false;
        m_cur_elect.finished = false;
        m_cur_elect.total_stake = total_stake;
        // return confirmation message
        if (query_id != 0) {
            return send_confirmation(query_id, 0);
        }
    }

    function unfreeze_without_bonuses(mapping(uint256 => Frozen) freeze_dict,
                                      uint128 tot_stakes) internal
            returns (uint128) {
        uint128 total = 0;
        uint128 recovered = 0;
        optional(uint256, Frozen) f = freeze_dict.min();
        while (f.hasValue()) {
            (uint256 pubkey, Frozen frozen) = f.get();
            if (frozen.banned) {
                recovered += frozen.stake;
            } else {
                credit_to(frozen.addr, frozen.stake);
            }
            total += frozen.stake;
            f = freeze_dict.next(pubkey);
        }
        require(total == tot_stakes, 59);
        return recovered;
    }

    function unfreeze_with_bonuses(mapping(uint256 => Frozen) freeze_dict,
                                   uint128 tot_stakes, uint128 tot_bonuses) internal
            returns (uint128) {
        uint128 total = 0;
        uint128 recovered = 0;
        uint128 returned_bonuses = 0;
        optional(uint256, Frozen) f = freeze_dict.min();
        while (f.hasValue()) {
            (uint256 pubkey, Frozen frozen) = f.get();
            if (frozen.banned) {
                recovered += frozen.stake;
            } else {
                (uint128 bonus, ) = math.muldivmod(tot_bonuses, frozen.stake, tot_stakes);
                returned_bonuses += bonus;
                credit_to(frozen.addr, frozen.stake + bonus);
            }
            total += frozen.stake;
            f = freeze_dict.next(pubkey);
        }
        require((total == tot_stakes) && (returned_bonuses <= tot_bonuses), 59);
        return recovered + tot_bonuses - returned_bonuses;
    }

    function stakes_sum(mapping(uint256 => Frozen) frozen_dict) internal pure returns (uint128) {
        uint128 total = 0;
        optional(uint256, Frozen) f = frozen_dict.min();
        while (f.hasValue()) {
            (uint256 pubkey, Frozen frozen) = f.get();
            total += frozen.stake;
            f = frozen_dict.next(pubkey);
        }
        return total;
    }

    function unfreeze_all(uint32 elect_id) internal returns (uint128) {
        optional(PastElection) p = m_past_elections.fetch(elect_id);
        if (!p.hasValue()) {
            return 0;
        }
        delete m_past_elections[elect_id];
        PastElection past = p.get();
        uint128 tot_stakes = past.total_stake;
        // tot_stakes = stakes_sum(p.frozen_dict); ;; TEMP BUGFIX
        if (past.bonuses > 0) {
            return unfreeze_with_bonuses(past.frozen_dict, tot_stakes, past.bonuses);
        }
        return unfreeze_without_bonuses(past.frozen_dict, tot_stakes);
    }

    function config_set_confirmed(uint64 query_id, bool ok) internal {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        (TvmCell cfg0, /* bool */) = tvm.rawConfigParam(0);
        uint256 config_addr = cfg0.toSlice().loadUnsigned(256);
        if (src_wc != -1 || src_addr != config_addr || !m_election_open) {
            // not from config smc, somebody's joke?
            // or no elections active (or just completed)
            return;
        }
        if (m_cur_elect.elect_at != query_id || !m_cur_elect.finished) {
            // not these elections, or elections not finished yet
            return;
        }
        tvm.accept();
        if (!ok) {
            // cancel elections, return stakes
            m_grams += unfreeze_all(m_cur_elect.elect_at);
            m_election_open = false;
        }
        // ... do not remove elect until we see this set as the next elected validator set
    }

    function config_set_confirmed_ok(uint64 query_id) override public
            functionID(0xee764f4b) onlyInternalMessage {
        config_set_confirmed(query_id, true);
    }

    function config_set_confirmed_err(uint64 query_id) override public
            functionID(0xee764f6f) onlyInternalMessage {
        config_set_confirmed(query_id, false);
    }

    function config_slash_confirmed_ok(uint64 query_id) override public
            functionID(0xee764f4c) onlyInternalMessage {
    }

    function config_slash_confirmed_err(uint64 query_id) override public
            functionID(0xee764f70) onlyInternalMessage {
    }

    function grant() override public functionID(0x4772616e) onlyInternalMessage {
        m_grams += msg.value;
    }

    function take_change() override public onlyInternalMessage {
    }

    function process_simple_transfer() internal {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (src_addr != 0 || src_wc != -1 || m_active_id == 0) {
            // simple transfer to us (credit "nobody's" account)
            // (or no known active validator set)
            msg.sender.transfer({value: 0, flag: 64});
            return;
        }
        // zero source address -1:00..00 (collecting validator fees)
        optional(PastElection) p = m_past_elections.fetch(m_active_id);
        if (!p.hasValue()) {
            // active validator set not found (?)
            m_grams += uint128(msg.value);
        } else {
            PastElection past = p.get();
            // credit active validator set bonuses
            past.bonuses += uint128(msg.value);
            m_past_elections[m_active_id] = past;
        }
    }

    function recover_stake(uint64 query_id) override public
            functionID(0x47657424) onlyInternalMessage {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (src_wc != -1) {
            // not from masterchain, return error
            send_message_back(msg.sender, 0xfffffffe, query_id, 0x47657424, 0, 64);
            return;
        }
        optional(uint128) amount = m_credits.fetch(src_addr);
        if (!amount.hasValue()) {
            // no credit for sender, return error
            send_message_back(msg.sender, 0xfffffffe, query_id, 0x47657424, 0, 64);
            return;
        }
        delete m_credits[src_addr];
        // send amount to sender in a new message
        IValidator(msg.sender).receive_stake_back{value: amount.get(), flag: 64}(query_id);
    }

    function recover_stake_gracefully(uint64 query_id, uint32 elect_id) override public
            functionID(0x47657425) onlyInternalMessage {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (src_wc != -1) {
            // not from masterchain, return error
            send_message_back(msg.sender, 0xfffffffe, query_id, 0x47657425, 0, 64);
            return;
        }
        optional(uint128) amount = m_credits.fetch(src_addr);
        if (!amount.hasValue()) {
            optional(PastElection) p = m_past_elections.fetch(elect_id);
            if (!p.hasValue()) {
                send_message_back(msg.sender, 0xfffffffe, query_id, 0x47657425, 0, 64);
                return;
            }
            PastElection past = p.get();
            send_message_back(msg.sender, 0xfffffffd, query_id, past.unfreeze_at, 0, 64);
            return;
        }
        delete m_credits[src_addr];
        // send amount to sender in a new message
        IValidator(msg.sender).receive_stake_back{value: amount.get(), flag: 64}(query_id);
    }

    function get_elect_at(uint64 query_id) override public
            functionID(0x47657426) onlyInternalMessage {
        (int8 src_wc, /*uint256 src_addr*/) = msg.sender.unpack();
        if (src_wc != -1) {
            // not from masterchain, return error
            send_message_back(msg.sender, 0xfffffffc, query_id, 0x47657426, 0, 64);
            return;
        }
        IValidator(msg.sender).receive_elect_at{value: 0, flag: 64}(query_id, m_election_open, m_cur_elect.elect_at);
    }

    function onCodeUpgrade(uint64 query_id) internal pure {
        send_message_back(msg.sender, 0xce436f64, query_id, 0x4e436f64, 0, 64);
    }

    function _upgrade_code(uint64 query_id, TvmCell code) internal pure returns (bool) {
        (TvmCell c_addr, bool f) = tvm.rawConfigParam(0);
        if (!f) {
            // no configuration smart contract known
            return false;
        }
        uint256 config_addr = c_addr.toSlice().loadUnsigned(256);
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (src_wc != -1 || src_addr != config_addr) {
            // not from configuration smart contract, return error
            return false;
        }
        tvm.accept();
        tvm.setcode(code);
        tvm.setCurrentCode(code);
        onCodeUpgrade(query_id);
        tvm.exit();
    }

    function upgrade_code(uint64 query_id, TvmCell code) override public
            functionID(0x4e436f64) onlyInternalMessage {
        bool ok = _upgrade_code(query_id, code);
        send_message_back(msg.sender, ok ? 0xce436f64 : 0xffffffff, query_id, 0x4e436f64, 0, 64);
    }

    function register_complaint(uint64 query_id, uint32 election_id, Complaint complaint) internal {
        int256 price = _register_complaint(election_id, complaint);
        uint8 mode = 64;
        int256 ans_tag = -price;
        if (price >= 0) {
            // ok, debit price
            tvm.rawReserve(uint256(price), 4);
            ans_tag = 0;
            mode = 128;
        }
        send_message_back(msg.sender, uint32(ans_tag) + 0xf2676350, query_id, 0x52674370, 0, mode);
    }

    function _register_complaint(uint32 election_id, Complaint complaint) internal
            returns (int256) {
        (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
        if (src_wc != -1) {
            // not from masterchain, return error
            return -1;
        }
        if (msg.data.depth() >= 128) {
            // invalid complaint
            return -3;
        }
        optional(PastElection) p = m_past_elections.fetch(election_id);
        if (!p.hasValue()) {
            // election not found
            return -2;
        }
        PastElection past = p.get();
        uint32 expire_in = past.unfreeze_at - now; // FIXME? overflow exception
        if (expire_in <= 0) {
            // already expired
            return -4;
        }
        require(complaint.tag == 0xbc, 9);
        uint32 created_at = now;
        // compute complaint storage/creation price
        (uint128 deposit, uint128 bit, uint128 cell) = get_complaint_prices();
        (uint128 bits, uint128 refs) = complaint.description.toSlice().size();
        uint128 pps = (bits + 1024) * bit + (refs + 2) * cell;
        uint128 paid = pps * expire_in + deposit;
        if (msg.value < paid + (1 << 30)) {
            // not enough money
            return -5;
        }
        complaint.created_at = created_at;
        complaint.reward_addr = src_addr;
        complaint.paid = paid;
        optional(Frozen) f = past.frozen_dict.fetch(complaint.validator_pubkey);
        if (!f.hasValue()) {
            // no such validator, cannot complain
            return -6;
        }
        Frozen frozen = f.get();
        uint128 validator_stake = frozen.stake;
        (uint128 fine_part, ) =
            math.muldivmod(validator_stake, complaint.suggested_fine_part, 1 << 32);
        uint128 fine = complaint.suggested_fine + fine_part;
        if (fine > validator_stake) {
            // validator's stake is less than suggested fine
            return -7;
        }
        if (fine <= paid) {
            // fine is less than the money paid for creating complaint
            return -8;
        }
        TvmBuilder b;
        b.store(complaint);
        TvmCell cpl = b.toCell();
        // create complaint status
        ComplaintStatus cstatus;
        cstatus.tag = 0x2d;
        cstatus.complaint = cpl;
        cstatus.vset_id = 0;
        cstatus.weight_remaining = 0;
        // save complaint status into complaints
        uint256 cpl_id = tvm.hash(cpl);
        if (!past.complaints.add(cpl_id, cstatus)) {
            // complaint already exists
            return -9;
        }
        m_past_elections[election_id] = past;
        return int256(paid);
    }

    function punish(mapping(uint256 => Frozen) frozen, TvmCell _complaint) internal
            returns (mapping(uint256 => Frozen), uint128, uint128) {
        Complaint complaint = _complaint.toSlice().decode(Complaint);
        optional(Frozen) f = frozen.fetch(complaint.validator_pubkey);
        if (!f.hasValue()) {
            // no validator to punish
            return (frozen, 0, 0);
        }
        Frozen fr = f.get();
        (uint128 fine_part, ) = math.muldivmod(fr.stake, complaint.suggested_fine_part, 1 << 32);
        uint128 fine = math.min(fr.stake, complaint.suggested_fine + fine_part);
        fr.stake -= fine;
        frozen[complaint.validator_pubkey] = fr;
        uint128 reward = math.min(fine >> 3, complaint.paid * 8);
        credit_to(complaint.reward_addr, reward);
        return (frozen, fine - reward, fine);
    }

    function register_vote(mapping(uint256 => ComplaintStatus) complaints,
                           uint256 chash, uint16 idx, int64 weight) internal pure
            returns (mapping(uint256 => ComplaintStatus),
                     TvmCell /* Complaint */, int32) {
        TvmCell nil;
        optional(ComplaintStatus) c = complaints.fetch(chash);
        if (!c.hasValue()) {
            // complaint not found
            return (complaints, nil, -1);
        }
        ComplaintStatus cstatus = c.get();
        (TvmCell cur_vset, uint64 total_weight, /* mapping(uint16 => TvmCell) */) = get_current_vset();
        uint256 cur_vset_id = tvm.hash(cur_vset);
        bool vset_old = (cstatus.vset_id != cur_vset_id);
        if ((cstatus.weight_remaining < 0) && vset_old) {
            // previous validator set already collected 2/3 votes, skip new votes
            return (complaints, nil, -3);
        }
        if (vset_old) {
            // complaint votes belong to a previous validator set, reset voting
            cstatus.vset_id = cur_vset_id;
            mapping(uint16 => uint32) voters;
            cstatus.voters = voters;
            (uint64 part, ) = math.muldivmod(total_weight, 2, 3);
            cstatus.weight_remaining = int64(part);
        }
        if (cstatus.voters.exists(idx)) {
            // already voted for this proposal, ignore vote
            return (complaints, nil, 0);
        }
        // register vote
        cstatus.voters[idx] = now;
        int64 old_wr = cstatus.weight_remaining;
        cstatus.weight_remaining -= weight;
        old_wr ^= cstatus.weight_remaining;
        // save voters and weight_remaining
        complaints[chash] = cstatus;
        if (old_wr >= 0) {
            // not enough votes or already accepted
            return (complaints, nil, 1);
        }
        // complaint wins, prepare punishment
        return (complaints, cstatus.complaint, 2);
    }

    function proceed_register_vote(uint64 query_id, uint256 signature_hi,
                                   uint256 signature_lo, uint32 sign_tag,
                                   uint16 idx, uint32 elect_id, uint256 chash)
            override public functionID(0x56744370) onlyInternalMessage {
        require(sign_tag == 0x56744350, 37);
        (/* TvmCell */, /* uint64 */, mapping(uint16 => TvmSlice) dict) =
            get_current_vset();
        optional(TvmSlice) vdescr = dict.fetch(idx);
        require(vdescr.hasValue(), 41);
        Common.Validator v = vdescr.get().decode(Common.Validator);
        require((v.tag & 0xdf) == 0x53, 41);
        require(v.ed25519_pubkey == 0x8e81278a, 41);

        TvmBuilder signature;
        signature.store(signature_hi, signature_lo);
        TvmBuilder msg_body;
        msg_body.store(sign_tag, idx, elect_id, chash);
        require(tvm.checkSign(msg_body.toSlice(), signature.toSlice(), v.pubkey), 34);

        int32 res = _proceed_register_vote(elect_id, chash, idx, int64(v.weight));
        send_message_back(msg.sender, uint32(res) + 0xd6745240, query_id, 0x56744370, 0, 64);
    }

    function _proceed_register_vote(uint32 election_id, uint256 chash,
                                    uint16 idx, int64 weight) internal
            returns (int32) {
        optional(PastElection) p = m_past_elections.fetch(election_id);
        if (!p.hasValue()) {
            // election not found
            return -2;
        }
        PastElection past = p.get();
        (mapping(uint256 => ComplaintStatus) complaints, TvmCell accepted_complaint, int32 status) =
            register_vote(past.complaints, chash, idx, weight);
        past.complaints = complaints;
        if (status <= 0) {
            return status;
        }
        if (status == 2) {
            (mapping(uint256 => Frozen) frozen_dict,
              uint128 fine_unalloc,
              uint128 fine_collected) =
                punish(past.frozen_dict, accepted_complaint);
            past.frozen_dict = frozen_dict;
            m_grams += fine_unalloc;
            past.total_stake -= fine_collected;
        }
        m_past_elections[election_id] = past;
        return status;
    }

    function postpone_elections() inline internal pure returns (bool) {
        return false;
    }

    struct List {
        uint128 stake;
        uint32 max_f;
        uint256 pubkey;
        uint256 adnl_addr;
        optional(List) tail;
    }

    struct EdgeStake {
        uint256 stake;
        uint16 id;
    }

    struct StakeAndFactor {
        uint128 stake;
        uint32 max_f;
    }

    // computes the total stake out of the first n entries of list l
    function compute_total_stake(optional(List) l, uint16 n, uint128 m_stake) internal pure inline
            returns (uint128) {
        uint128 tot_stake = 0;
        repeat(n) {
            List h = l.get();
            tot_stake += math.min(h.stake, ((h.max_f) * m_stake) >> 16);
            l = h.tail;
        }
        return tot_stake;
    }

    struct Key {
        uint128 stake;
        int32 time;
        uint256 pubkey;
    }

    struct Value {
        uint32 max_f;
        uint256 addr;
        uint256 adnl_addr;
    }

    function try_elect(uint128 min_stake, uint128 max_stake,
                       uint128 min_total_stake, uint32 max_stake_factor) internal inline
            returns (mapping(uint16 => TvmSlice), uint64, mapping(uint256 => Frozen), uint128, uint16) {
        (TvmCell cfg16, /* bool */) = tvm.rawConfigParam(16);
        (uint16 max_validators, /* uint16 */, uint16 min_validators) = cfg16.toSlice().decode(uint16, uint16, uint16);
        min_validators = math.max(min_validators, 1);
        uint16 n = 0;
        mapping(Key => Value) sdict;
        mapping(uint256 => Member) members = m_cur_elect.members;
        for ((uint256 pkey, Member _mem) : members) {
            (uint128 stake, uint32 time, uint32 max_factor, uint256 addr, uint256 adnl_addr) = _mem.unpack();
            sdict[Key(stake, -int32(time), pkey)] =
                Value(math.min(max_factor, max_stake_factor), addr, adnl_addr);
            ++n;
        }
        n = math.min(n, max_validators);
        if (n < min_validators) {
            mapping(uint16 => TvmSlice) nil1;
            mapping(uint256 => Frozen) nil2;
            return (nil1, 0, nil2, 0, 0);
        }
        optional(List) l;
        for ((Key key, Value value) : sdict) {
            uint128 stake = math.min(key.stake, max_stake);
            l = List({
                stake: stake,
                max_f: value.max_f,
                pubkey: key.pubkey,
                adnl_addr: value.adnl_addr,
                tail: l
            });
        }

        // l is the list of all stakes in decreasing order
        uint128 m_stake = 0; // minimal stake
        uint128 best_stake = 0;
        uint16 m = 0;
        optional(List) l1 = l;

        uint128 wholeStakeSum = 0;
        mapping(EdgeStake => StakeAndFactor) wholeStakes;
        uint128 cutFactSum = 0;

        for (uint16 qty = 1; qty <= n; ++qty) {
            List list1 = l1.get();
            uint128 stake = list1.stake;
            if (stake < min_stake) {
                break;
            }
            uint32 max_f = list1.max_f;
            l1 = list1.tail;

            wholeStakeSum += stake;
            uint256 edgeStake = (uint256(stake) * uint256(65536) * PRECISION) / max_f; // 128+16+64-32
            wholeStakes[EdgeStake(edgeStake, qty)] = StakeAndFactor(stake, max_f);

            while (!wholeStakes.empty()) {
                (EdgeStake es, StakeAndFactor sf) = wholeStakes.max().get();
                if (es.stake < stake * PRECISION) {
                    break;
                }
                wholeStakeSum -= sf.stake;
                wholeStakes.delMax();
                cutFactSum += sf.max_f;
            }

            uint128 tot_stake = wholeStakeSum + uint128((uint256(stake) * cutFactSum) >> 16);
            if (tot_stake > best_stake) {
                best_stake = tot_stake;
                m = qty;
                m_stake = stake;
            }
        }

        if ((m == 0) || (best_stake < min_total_stake)) {
            mapping(uint16 => TvmSlice) nil1;
            mapping(uint256 => Frozen) nil2;
            return (nil1, 0, nil2, 0, 0);
        }
        // we have to select first m validators from list l

        // precise calculation of best stake
        {
            uint128 round_best_stake = best_stake;
            best_stake = 0;
            l1 = l;
            repeat(m) {
                List list1 = l1.get();
                best_stake += math.min(list1.stake, m_stake * list1.max_f >> 16);
                l1 = list1.tail;
            }
            require(math.abs(int(round_best_stake) - int(best_stake)) <= 1 ton, 666);
        }

        // create both the new validator set and the refund set
        uint16 i = 0;
        uint128 tot_stake = 0;
        uint128 tot_weight = 0;
        mapping(uint16 => TvmSlice) vset;
        mapping(uint256 => Frozen) frozen;
        mapping(uint256 => uint128) credits = m_credits;
        do {
            (uint128 stake, uint32 max_f, uint256 pubkey, uint256 adnl_addr, optional(List) tail) = l.get().unpack();
            l = tail;
            // lookup source address first
            optional(Member) mem = members.fetch(pubkey);
            require(mem.hasValue(), 61);
            uint256 src_addr = mem.get().addr;
            if (i < m) {
                // one of the first m members, include into validator set
                uint128 true_stake = math.min(stake, (max_f * m_stake) >> 16);
                stake -= true_stake;
                uint128 weight = (true_stake << 60) / best_stake;
                tot_stake += true_stake;
                tot_weight += weight;
                TvmBuilder vinfo;
                if (adnl_addr > 0) {
                    vinfo.store(Common.ValidatorAddr(0x73, 0x8e81278a, pubkey,
                                                     uint64(weight), adnl_addr));
                } else {
                    vinfo.store(Common.Validator(0x53, 0x8e81278a, pubkey,
                                                 uint64(weight)));
                }
                vset[i] = vinfo.toSlice();
                frozen[pubkey] = Frozen(src_addr, uint64(weight), true_stake, false);
            }
            if (stake > 0) {
                // non-zero unused part of the stake, credit to the source address
                // credit_to(src_addr, stake);
                credits[src_addr] += stake;
            }
            i += 1;
        } while (l.hasValue());
        m_credits = credits;
        require(tot_stake == best_stake, 49);
        return (vset, uint64(tot_weight), frozen, tot_stake, m);
    }

    function conduct_elections() internal returns (bool) {
        Elect cur_elect = m_cur_elect;
        if (now < cur_elect.elect_close) {
            // elections not finished yet
            return false;
        }
        (/* TvmCell */, bool f) = tvm.rawConfigParam(0);
        if (!f) {
            // no configuration smart contract to send result to
            return postpone_elections();
        }
        (uint128 min_stake, uint128 max_stake, uint128 min_total_stake,
          uint32 max_stake_factor, /* bool */) = tvm.configParam(17);
        if (cur_elect.total_stake < min_total_stake) {
            // insufficient total stake, postpone elections
            return postpone_elections();
        }
        if (cur_elect.failed) {
            // do not retry failed elections until new stakes arrive
            return postpone_elections();
        }
        if (cur_elect.finished) {
            // elections finished
            return false;
        }
        (mapping(uint16 => TvmSlice) vdict, uint64 total_weight,
         mapping(uint256 => Frozen) frozen, uint128 total_stakes, uint16 cnt) =
            try_elect(min_stake, max_stake, min_total_stake, max_stake_factor);
        // pack elections; if cnt==0, set failed=true, finished=false.
        cur_elect.failed = (cnt == 0);
        cur_elect.finished = !cur_elect.failed;
        m_cur_elect = cur_elect;
        if (cnt == 0) {
            // elections failed, set elect_failed to true
            return postpone_elections();
        }
        uint32 cur_elect_at = cur_elect.elect_at;
        // serialize a query to the configuration smart contract
        // to install the computed validator set as the next validator set
        (uint32 elect_for, /* uint32 */, uint32 elect_end_before, uint32 stake_held) =
            get_validator_conf();
        uint32 start = math.max(now + elect_end_before - 60, cur_elect_at);
        (TvmCell cfg16, /* bool */) = tvm.rawConfigParam(16);
        (/* uint16 */, uint16 main_validators) = cfg16.toSlice().decode(uint16, uint16);

        // Common.ValidatorSet vset;
        TvmBuilder b;
        b.store(uint8(0x12), start, start + elect_for, cnt, math.min(cnt, main_validators),
                total_weight, vdict);
        TvmCell vsetCell = b.toCell();

        (TvmCell cfg0, /* bool */) = tvm.rawConfigParam(0);
        uint256 config_addr = cfg0.toSlice().loadUnsigned(256);
        send_validator_set_to_config(config_addr, vsetCell, cur_elect_at);
        // add frozen to the dictionary of past elections
        PastElection past;
        past.unfreeze_at = start + elect_for + stake_held;
        past.stake_held = stake_held;
        past.vset_hash = tvm.hash(vsetCell);
        past.frozen_dict = frozen;
        past.total_stake = total_stakes;
        m_past_elections[cur_elect_at] = past;
        // reset slasher
        mapping(uint256 => bool) nil1;
        m_banned = nil1;
        mapping(uint256 => mapping(uint8 => Bucket)) nil2;
        m_reports = nil2;
        m_reports_workchain = nil2;

        optional(uint16, TvmSlice) v = vdict.min();
        uint64 masterchain_vtors_weight = 0;
        uint64 workchain_vtors_weight = 0;
        uint16 index = 0;
        while (v.hasValue()) {
            (uint16 id, TvmSlice entry) = v.get();
            Common.ValidatorAddr vtor = entry.decode(Common.ValidatorAddr);
            require(vtor.tag == 0x73, BAD_CONFIG_PARAM_34);
            if (index < main_validators) {
                masterchain_vtors_weight += vtor.weight;
            } else {
                workchain_vtors_weight += vtor.weight;
            }
            index += 1;
            v = vdict.next(id);
        }
        m_masterchain_vtors_weight = masterchain_vtors_weight;
        m_workchain_vtors_weight = workchain_vtors_weight;

        return true;
    }

    function update_active_vset_id() internal returns (bool) {
        (TvmCell cfg34, /* bool */) = tvm.rawConfigParam(34);
        uint256 cur_hash = tvm.hash(cfg34);
        if (cur_hash == m_active_hash) {
            // validator set unchanged
            return false;
        }
        if (m_active_id != 0) {
            // active_id becomes inactive
            optional(PastElection) p = m_past_elections.fetch(m_active_id);
            if (p.hasValue()) {
                PastElection past = p.get();
                // adjust unfreeze time of this validator set
                require(past.vset_hash == m_active_hash, 57);
                past.unfreeze_at = now + past.stake_held;
                m_past_elections[m_active_id] = past;
            }
        }
        // look up new active_id by hash
        optional(uint32, PastElection) p = m_past_elections.min();
        while (p.hasValue()) {
            (uint32 id, PastElection past) = p.get();
            if (past.vset_hash == cur_hash) {
                // transfer 1/8 of accumulated everybody's grams to this validator set as bonuses
                uint128 amount = (m_grams >> 3);
                m_grams -= amount;
                past.bonuses += amount;
                m_past_elections[id] = past;
                // found
                break;
            }
            p = m_past_elections.next(id);
        }
        if (p.hasValue()) {
            (uint32 id, ) = p.get();
            m_active_id = id;
        } else {
            m_active_id = 0;
        }
        m_active_hash = cur_hash;
        return true;
    }

    function validator_set_installed() internal returns (bool) {
        if (!m_cur_elect.finished) {
            // elections not finished yet
            return false;
        }
        optional(PastElection) p = m_past_elections.fetch(m_cur_elect.elect_at);
        if (!p.hasValue()) {
            // no election data in dictionary
            return false;
        }
        PastElection past = p.get();
        // recover validator set hash
        (TvmCell cfg34, bool f1) = tvm.rawConfigParam(34);
        (TvmCell cfg36, bool f2) = tvm.rawConfigParam(36);
        if ((f1 && (tvm.hash(cfg34) == past.vset_hash)) ||
            (f2 && (tvm.hash(cfg36) == past.vset_hash))) {
            // this validator set has been installed, forget elections
            m_election_open = false;
            Elect elect;
            m_cur_elect = elect;
            update_active_vset_id();
            return true;
        }
        return false;
    }

    function check_unfreeze() internal {
        optional(uint32, PastElection) p = m_past_elections.min();
        while (p.hasValue()) {
            (uint32 id, PastElection past) = p.get();
            if ((past.unfreeze_at <= now) && (id != m_active_id)) {
                // unfreeze!
                m_grams += unfreeze_all(id);
                // unfreeze only one at time, exit loop
                break;
            }
            p = m_past_elections.next(id);
        }
    }

    function announce_new_elections() internal returns (bool) {
        (/* TvmCell */, bool f) = tvm.rawConfigParam(36); // next validator set
        if (f) {
            // next validator set exists, no elections needed
            return false;
        }
        (TvmCell cfg1, /* bool */) = tvm.rawConfigParam(1);
        uint256 elector_addr = cfg1.toSlice().loadUnsigned(256);
        (int8 my_wc, uint256 my_addr) = address(this).unpack();
        if ((my_wc != -1) || (my_addr != elector_addr)) {
            // this smart contract is not the elections smart contract anymore, no new elections
            return false;
        }
        (TvmCell cur_vset, bool f2) = tvm.rawConfigParam(34); // current validator set
        if (!f2) {
            return false;
        }
        (/* uint32 */, uint32 elect_begin_before, uint32 elect_end_before, /* uint32 */) = get_validator_conf();
        (/* uint8 */ /* uint32 */, uint32 cur_valid_until) = cur_vset.toSlice().decode(uint40, uint32);
        uint32 t = now;
        uint32 t0 = cur_valid_until - elect_begin_before;
        if (t < t0) {
            // too early for the next elections
            return false;
        }
        // less than elect_before_begin seconds left, create new elections
        if (t - t0 < 60) {
            // pretend that the elections started at t0
            t = t0;
        }
        // get stake parameters
        (uint128 min_stake, /* uint128 */, /* uint128 */, /* uint32 */, /* bool */) = tvm.configParam(17);
        // announce new elections
        uint32 elect_at = t + elect_begin_before;
        // elect_at~dump();
        uint32 elect_close = elect_at - elect_end_before;
        Elect n_elect = Elect(elect_at, elect_close, min_stake, 0,
                              false, false);
        m_cur_elect = n_elect;
        m_election_open = true;
        return true;
    }

    onTickTock(bool /* is_tock */) external {
        // check whether an election is being conducted
        if (m_election_open) {
            // have an active election
            if (conduct_elections()) {
                // elections conducted, exit
                return;
            }
            if (validator_set_installed()) {
                // validator set installed, current elections removed
                return;
            }
        } else {
            if (announce_new_elections()) {
                // new elections announced, exit
                return;
            }
        }
        if (update_active_vset_id()) {
            // active validator set id updated, exit
            return;
        }
        check_unfreeze();
    }

    uint8 constant BAD_CONFIG_PARAM_1      = 130;
    uint8 constant BAD_CONFIG_PARAM_34     = 131;
    uint8 constant BAD_REPORTER_PUBKEY     = 132;
    uint8 constant BAD_VICTIM_PUBKEY       = 133;
    uint8 constant BAD_SIGNATURE           = 134;
    uint8 constant BAD_REPORTER_WEIGHT     = 135;
    uint8 constant BAD_ACTIVE_ID           = 136;
    uint8 constant BAD_BANNED_REPORTER     = 137;
    uint8 constant BAD_BANNED_VICTIM       = 138;
    uint8 constant BAD_REPORT_TIME         = 139;
    uint8 constant BAD_REPORT_DUPLICATE    = 140;
    uint8 constant BAD_TOTAL_VTORS         = 141;

    uint64 m_masterchain_vtors_weight;
    uint64 m_workchain_vtors_weight;

    mapping(uint256 => bool) m_banned;

    struct Bucket {
        uint64 weight;
        mapping(uint256 => uint64) reports;
    }

    mapping(uint256 => mapping(uint8 => Bucket)) m_reports;

    uint64 constant THRESHOLD_MASTERCHAIN_NUMERATOR   = 2;
    uint64 constant THRESHOLD_MASTERCHAIN_DENOMINATOR = 3;

    mapping(uint256 => mapping(uint8 => Bucket)) m_reports_workchain;

    uint64 constant THRESHOLD_WORKCHAIN_NUMERATOR   = 1;
    uint64 constant THRESHOLD_WORKCHAIN_DENOMINATOR = 3;

    function report(uint256 signature_hi, uint256 signature_lo, uint256 reporter_pubkey, uint256 victim_pubkey, uint8 metric_id) override public {
        // ignore reports from already banned reporters
        require(!m_banned.exists(reporter_pubkey), BAD_BANNED_REPORTER);

        // ignore reports about already banned reportees
        require(!m_banned.exists(victim_pubkey), BAD_BANNED_VICTIM);

        (TvmCell info, ) = tvm.rawConfigParam(34);
        Common.ValidatorSet vset = info.toSlice().decode(Common.ValidatorSet);
        require(vset.tag == 0x12, BAD_CONFIG_PARAM_34);

        // ignore reports outside of the vset's active time interval
        require(vset.utime_since < now && now < vset.utime_until, BAD_REPORT_TIME);

        TvmBuilder signature;
        signature.store(signature_hi, signature_lo);
        TvmBuilder msg_body;
        msg_body.store(reporter_pubkey, victim_pubkey, metric_id);
        require(tvm.checkSign(msg_body.toSlice(), signature.toSlice(), reporter_pubkey),
                BAD_SIGNATURE);

        // accept external message
        tvm.accept();

        optional(uint16, TvmSlice) v = vset.vdict.min();
        uint64 reporter_weight = 0;
        uint16 reporter_index = 0;
        while (v.hasValue()) {
            (uint16 id, TvmSlice entry) = v.get();
            Common.ValidatorAddr vtor = entry.decode(Common.ValidatorAddr);
            require(vtor.tag == 0x73, BAD_CONFIG_PARAM_34);
            if (vtor.pubkey == reporter_pubkey) {
                reporter_weight = vtor.weight;
                break;
            }
            reporter_index += 1;
            v = vset.vdict.next(id);
        }
        require(reporter_weight > 0, BAD_REPORTER_WEIGHT);

        v = vset.vdict.min();
        bool victim_found = false;
        while (v.hasValue()) {
            (uint16 id, TvmSlice entry) = v.get();
            Common.ValidatorAddr vtor = entry.decode(Common.ValidatorAddr);
            require(vtor.tag == 0x73, BAD_CONFIG_PARAM_34);
            if (vtor.pubkey == victim_pubkey) {
                victim_found = true;
                break;
            }
            v = vset.vdict.next(id);
        }
        require(victim_found, BAD_VICTIM_PUBKEY);

        (TvmCell cfg16, ) = tvm.rawConfigParam(16);
        ( , uint16 max_main_validators) = cfg16.toSlice().decode(uint16, uint16);

        if (reporter_index < max_main_validators) {
            Bucket bucket = m_reports[victim_pubkey][metric_id];
            optional(uint64) exists = bucket.reports.fetch(reporter_pubkey);
            // proceed only if the reporter hasn't yet reported
            require(!exists.hasValue(), BAD_REPORT_DUPLICATE);

            bucket.weight += reporter_weight;
            bucket.reports[reporter_pubkey] = reporter_weight;
            m_reports[victim_pubkey][metric_id] = bucket;
            tvm.commit();

            if (bucket.weight >= math.muldiv(m_masterchain_vtors_weight,
                    THRESHOLD_MASTERCHAIN_NUMERATOR, THRESHOLD_MASTERCHAIN_DENOMINATOR)) {
                // slashing condition is met
                m_banned[victim_pubkey] = true;
                emit_updated_validator_set();
            }
        } else {
            Bucket bucket = m_reports_workchain[victim_pubkey][metric_id];
            optional(uint64) exists = bucket.reports.fetch(reporter_pubkey);
            // proceed only if the reporter hasn't yet reported
            require(!exists.hasValue(), BAD_REPORT_DUPLICATE);

            bucket.weight += reporter_weight;
            bucket.reports[reporter_pubkey] = reporter_weight;
            m_reports[victim_pubkey][metric_id] = bucket;
            tvm.commit();

            if (bucket.weight >= math.muldiv(m_workchain_vtors_weight,
                    THRESHOLD_WORKCHAIN_NUMERATOR, THRESHOLD_WORKCHAIN_DENOMINATOR)) {
                // slashing condition is met
                m_banned[victim_pubkey] = true;
                emit_updated_validator_set();
            }
        }
    }

    function afterSignatureCheck(TvmSlice body, TvmCell) private inline pure returns (TvmSlice) {
        body.decode(uint64);
        // no replay protection
        return body;
    }

    function emit_updated_validator_set() internal inline {
        (TvmCell info, ) = tvm.rawConfigParam(34);
        Common.ValidatorSet vset = info.toSlice().decode(Common.ValidatorSet);
        require(vset.tag == 0x12, BAD_CONFIG_PARAM_34);

        mapping(uint16 => TvmSlice) vdict_updated;
        uint64 total_weight = 0;
        optional(uint16, TvmSlice) v = vset.vdict.min();
        uint16 index = 0;
        while (v.hasValue()) {
            (uint16 id, TvmSlice entry) = v.get();
            Common.ValidatorAddr vtor = entry.decode(Common.ValidatorAddr);
            require(vtor.tag == 0x73, BAD_CONFIG_PARAM_34);
            if (!m_banned.exists(vtor.pubkey)) {
                (, TvmSlice s) = v.get();
                vdict_updated[index] = s;
                total_weight += vtor.weight;
                index += 1;
            }
            v = vset.vdict.next(id);
        }

        (TvmCell p16, ) = tvm.rawConfigParam(16);
        (, , uint16 min_validators) = p16.toSlice().decode(uint16, uint16, uint16);
        require(index >= min_validators, BAD_TOTAL_VTORS);

        Common.ValidatorSet vset_updated = vset;
        vset_updated.utime_since  = now + 60;
        vset_updated.total_weight = total_weight;
        vset_updated.total        = index;
        vset_updated.main         = math.min(index, vset.main);
        vset_updated.vdict        = vdict_updated;

        TvmBuilder b;
        b.store(vset_updated);
        TvmCell vset_updated_cell = b.toCell();

        optional(PastElection) p = m_past_elections.fetch(m_active_id);
        require(p.hasValue(), BAD_ACTIVE_ID);
        PastElection past = p.get();

        uint256 active_hash = tvm.hash(vset_updated_cell);
        m_active_hash = active_hash;
        past.vset_hash = active_hash;
        m_past_elections[m_active_id] = past;

        (TvmCell cfg0, ) = tvm.rawConfigParam(0);
        address config_addr = address.makeAddrStd(-1, cfg0.toSlice().loadUnsigned(256));
        IConfig(config_addr).set_slashed_validator_set{value: (1 << 30), flag: 1}(m_active_id, vset_updated_cell);
    }

    // Get complete storage
    function get() public view
        returns (
            bool election_open,
            Elect cur_elect,
            mapping(uint256 => uint128) credits,
            mapping(uint32 => PastElection) past_elections,
            uint128 grams,
            uint32 active_id,
            uint256 active_hash
        )
    {
        election_open  = m_election_open;
        cur_elect      = m_cur_elect;
        credits        = m_credits;
        past_elections = m_past_elections;
        grams          = m_grams;
        active_id      = m_active_id;
        active_hash    = m_active_hash;
    }

    function get_banned() public view returns (mapping(uint256 => bool)) {
        return m_banned;
    }

    function get_buckets(uint256 victim_pubkey) public view returns (mapping(uint8 => Bucket)) {
        return m_reports[victim_pubkey];
    }

    function get_buckets_workchain(uint256 victim_pubkey) public view returns (mapping(uint8 => Bucket)) {
        return m_reports_workchain[victim_pubkey];
    }

    // Get methods TODO remove

    // returns active election id or 0
    function active_election_id() public view returns (uint32) {
        return m_election_open ? m_cur_elect.elect_at : 0;
    }

    // computes the return stake
    function compute_returned_stake(uint256 wallet_addr) public view returns (uint256) {
        optional(uint128) v = m_credits.fetch(wallet_addr);
        return v.hasValue() ? v.get() : 0;
    }

    onBounce(TvmSlice slice) external {
        uint32 id = slice.decode(uint32);
        if (id == tvm.functionId(IValidator.receive_stake_back)) {
            (int8 src_wc, uint256 src_addr) = msg.sender.unpack();
            require(src_wc == -1, 223);
            m_credits[src_addr] = msg.value;
        }
    }

    receive() external {
        // inbound message has empty body
        // simple transfer with comment, return
        process_simple_transfer();
    }

    fallback() external {
        TvmSlice s = msg.data;
        uint32 op = s.loadUnsigned(32);
        uint64 query_id = s.loadUnsigned(64);
        if (op == 0x52674370) { // register_complaint
            uint32 election_id            = s.loadUnsigned(32);
            Complaint complaint;
            complaint.tag                 = s.loadUnsigned(8);
            complaint.validator_pubkey    = s.loadUnsigned(256);
            complaint.description         = s.loadRef();
            complaint.created_at          = s.loadUnsigned(32);
            complaint.severity            = s.loadUnsigned(8);
            complaint.reward_addr         = s.loadUnsigned(256);
            complaint.paid                = s.loadTons();
            complaint.suggested_fine      = s.loadTons();
            complaint.suggested_fine_part = s.loadUnsigned(32);
            register_complaint(query_id, election_id, complaint);
        } else if ((op & (1 << 31)) == 0) {
            send_message_back(msg.sender, 0xffffffff, query_id, op, 0, 64);
        }
    }

    modifier onlyInternalMessage() {
        require(msg.sender != address(0), 222);
        _;
    }
}
