/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2023 (c) EverX
*/

pragma ton-solidity >=0.66.0;
pragma AbiHeader expire;
pragma AbiHeader time;
import "IConfig.sol";
import "IElector.sol";
import "Common.sol";

// pragma upgrade func; // uncomment if you want update

contract Config is IConfig {

    struct __ValidatorSet {
        uint8 tag; // = 0x12
        uint32 utime_since;
        uint32 utime_until;
        uint16 total;
        uint16 main;
        uint64 total_weight;
        mapping(uint16 => Common.ValidatorAddr) vdict;
    }

    mapping(uint32 => TvmCell) m_cfg_dict;

    // constructor for tests
    constructor(
        // param 1
        uint256 elector_addr,
        // param 15
        uint32 elect_for,
        uint32 elect_begin_before,
        uint32 elect_end_before,
        uint32 stake_held,
        // param 16
        uint16 max_validators,
        uint16 main_validators,
        uint16 min_validators,
        // param 17
        uint128 min_stake,
        uint128 max_stake,
        uint128 min_total_stake,
        uint32 max_stake_factor,
        // param 34
        uint32 utime_since,
        uint32 utime_until,
        // param
        uint256 public_key
    ) public {
        tvm.setPubkey(public_key);
        {
            TvmBuilder b;
            b.store(elector_addr);
            m_cfg_dict[1] = b.toCell();
        }
        // {
        //     TvmBuilder b;
        //     b.store(uint8(0xC4));
        //     b.store(uint32(32));
        //     b.store(uint64(0x2e));
        //     m_cfg_dict[8] = b.toCell();
        // }
        {
            TvmBuilder b;
            b.store(uint8(0x1a));
            b.storeTons(1 << 30);
            b.storeTons(1);
            b.storeTons(512);
            m_cfg_dict[13] = b.toCell();
        }
        {
            TvmBuilder b;
            b.store(elect_for, elect_begin_before, elect_end_before, stake_held);
            m_cfg_dict[15] = b.toCell();
        }
        {
            TvmBuilder b;
            b.store(max_validators, main_validators, min_validators);
            m_cfg_dict[16] = b.toCell();
        }
        {
            TvmBuilder b;
            b.storeTons(min_stake);
            b.storeTons(max_stake);
            b.storeTons(min_total_stake);
            b.store(max_stake_factor);
            m_cfg_dict[17] = b.toCell();
        }
        {
            Common.ValidatorSet vset;
            vset.tag          = 0x12;
            vset.utime_since  = utime_since;
            vset.utime_until  = utime_until;
            vset.total        = 0;
            vset.main         = 0;
            vset.total_weight = 0;

            mapping(uint16 => TvmSlice) vdict;
            vset.vdict = vdict;

            TvmBuilder b;
            b.store(vset);
            m_cfg_dict[34] = b.toCell();
        }
    }

/*
    bit#_ _:(## 1) = Bit;

    hm_edge#_ {n:#} {X:Type} {l:#} {m:#} label:(HmLabel ~l n)
              {n = (~m) + l} node:(HashmapNode m X) = Hashmap n X;

    hmn_leaf#_ {X:Type} value:X = HashmapNode 0 X;
    hmn_fork#_ {n:#} {X:Type} left:^(Hashmap n X)
               right:^(Hashmap n X) = HashmapNode (n + 1) X;

    hml_short$0 {m:#} {n:#} len:(Unary ~n)
                s:(n * Bit) = HmLabel ~n m;
    hml_long$10 {m:#} n:(#<= m) s:(n * Bit) = HmLabel ~n m;
    hml_same$11 {m:#} v:Bit n:(#<= m) = HmLabel ~n m;

    unary_zero$0 = Unary ~0;
    unary_succ$1 {n:#} x:(Unary ~n) = Unary ~(n + 1);

    hme_empty$0 {X:Type} = HashmapE n X;
    hme_root$1 {X:Type} root:^(Hashmap n X) = HashmapE n X;
*/

    function ubitsize(uint16 n) internal pure returns (uint16) {
        uint16 size = 0;
        while (n > 0) {
            n /= 2;
            size += 1;
        }
        return size;
    }

    function check_node(TvmSlice slice, uint16 n) internal pure returns (TvmSlice) {
        if (n == 0) {
            uint8 tag = slice.loadUnsigned(8);
            require(tag == 0x73, 195);
            uint16 remaining = 616 - 8; // sizeof(Common.ValidatorAddr) - sizeof(tag)
            slice.loadSlice(remaining);
        } else {
            TvmCell left = slice.loadRef();
            TvmCell right = slice.loadRef();
            check_hashmap(left, n - 1);
            check_hashmap(right, n - 1);
        }
        return slice;
    }

    function check_hashmap(TvmCell root, uint16 n) internal pure {
        TvmSlice slice = root.toSlice();
        (TvmSlice slice_prime, uint16 l) = check_label(slice, n);
        slice = slice_prime;
        slice = check_node(slice, n - l);
        require(slice.bits() == 0, 193);
        require(slice.refs() == 0, 194);
    }

    function check_label(TvmSlice slice, uint16 m) internal pure returns (TvmSlice, uint16) {
        uint16 n = 0;
        uint8 first_bit = slice.loadUnsigned(1);
        if (first_bit == 0) {
            while (slice.loadUnsigned(1) == 1) {
                n += 1;
            }
            slice.loadUnsigned(n);
        } else {
            uint8 second_bit = slice.loadUnsigned(1);
            if (second_bit == 0) {
                n = slice.loadUnsigned(ubitsize(m));
                slice.loadUnsigned(n);
            } else {
                slice.loadUnsigned(1);
                n = slice.loadUnsigned(ubitsize(m));
            }
        }
        return (slice, n);
    }

    function check_dict_u16_slice616(TvmSlice slice) internal pure returns (TvmSlice) {
        uint8 first_bit = slice.loadUnsigned(1);
        if (first_bit == 1) {
            TvmCell root = slice.loadRef();
            check_hashmap(root, 16);
        }
        return slice;
    }

    function check_validator_set_tlb(TvmCell vset) internal pure {
        TvmSlice slice = vset.toSlice();
        uint8 tag = slice.loadUnsigned(8);
        require(tag == 0x12, 199);
        slice.loadUnsigned(32);
        slice.loadUnsigned(32);
        slice.loadUnsigned(16);
        slice.loadUnsigned(16);
        slice.loadUnsigned(64);
        slice = check_dict_u16_slice616(slice);
        require(slice.bits() == 0, 191);
        require(slice.refs() == 0, 192);
    }

    function check_validator_set(TvmCell vset) internal pure returns (uint32, uint32) {
        check_validator_set_tlb(vset);
        Common.ValidatorSet v = vset.toSlice().decode(Common.ValidatorSet);
        require(v.tag == 0x12, 9);
        require(v.main > 0, 9);
        require(v.total >= v.main, 9);

        uint16 index = v.total;
        optional(uint16, TvmSlice) e = v.vdict.max();
        while (e.hasValue()) {
            index -= 1;
            (uint16 id, TvmSlice entry) = e.get();
            require(id == index, 111);
            Common.ValidatorAddr vtor = entry.decode(Common.ValidatorAddr);
            require(vtor.tag == 0x73, 9);
            e = v.vdict.prev(id);
        }

        return (v.utime_since, v.utime_until);
    }

    function send_confirmation(uint64 query_id) internal pure {
        IElector(msg.sender).config_set_confirmed_ok{flag: 64, value: 0}(query_id);
    }

    function send_error(uint64 query_id) internal pure {
        IElector(msg.sender).config_set_confirmed_err{flag: 64, value: 0}(query_id);
    }

    function send_slash_confirmation(uint64 query_id) internal pure {
        IElector(msg.sender).config_slash_confirmed_ok{flag: 64, value: 0}(query_id);
    }

    function send_slash_error(uint64 query_id) internal pure {
        IElector(msg.sender).config_slash_confirmed_err{flag: 64, value: 0}(query_id);
    }

    function set_next_validator_set(uint64 query_id, TvmCell vset) override
        functionID(0x4e565354) public {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        if (!f) {
            return;
        }
        uint256 elector_addr = cfg1.toSlice().loadUnsigned(256);
        bool ok = false;
        if (msg.sender.value == elector_addr) {
            // message from elector smart contract
            // set next validator set
            (uint32 t_since, uint32 t_until) = check_validator_set(vset);
            ok = (t_since > now) && (t_until > t_since);
        }
        if (ok) {
            m_cfg_dict[36] = vset;
            // send confirmation
            send_confirmation(query_id);
        } else {
            send_error(query_id);
        }
    }

    function set_slashed_validator_set(uint64 query_id, TvmCell vset) override
        functionID(0x4e565355) public {
        (int8 my_wc, /* uint256 */) = address(this).unpack();
        if (my_wc != -1) {
            return;
        }
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        if (!f) {
            return;
        }
        uint256 elector_addr = cfg1.toSlice().loadUnsigned(256);
        bool ok = false;
        if (msg.sender.value == elector_addr) {
            // message from elector smart contract
            // set slashed validator set
            (uint32 t_since, uint32 t_until) = check_validator_set(vset);
            ok = (t_since > now) && (t_until > t_since);
        }
        if (ok) {
            m_cfg_dict[35] = vset;
            // send confirmation
            send_slash_confirmation(query_id);
        } else {
            send_slash_error(query_id);
        }
    }

    // we accept external corrtly signed messages only
    modifier requireOwner {
        require(tvm.pubkey() != 0, 101);
        require(tvm.pubkey() == msg.pubkey(), 100);
        _;
    }

    function set_config_param(uint32 index, TvmCell data) public externalMsg requireOwner {
        require(data.toSlice().depth() <= 128, 39);
        tvm.accept();
        m_cfg_dict[index] = data;
    }

    function set_public_key(uint256 public_key) public externalMsg requireOwner {
        tvm.accept();
        tvm.setPubkey(public_key);
    }

    function set_elector_code(TvmCell code, TvmCell data) public externalMsg view requireOwner {
        require(code.depth() <= 128, 39);
        require(data.depth() <= 128, 39);
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        if (!f) {
            return;
        }
        tvm.accept();
        uint256 elector_addr = cfg1.toSlice().loadUnsigned(256);
        uint32 query_id = now;
        IElector(address.makeAddrStd(-1, elector_addr))
            .upgrade_code{value: 1 << 30, flag: 0}(query_id, code, data);
    }

    function set_code(TvmCell code) public externalMsg requireOwner {
        require(code.depth() <= 128, 39);
        tvm.setcode(code);
        onCodeUpgrade();
    }

    // we accept internal message from approved contract only
    modifier requireOwnerContract {
        (TvmCell cfg5, bool f) = tvm.rawConfigParam(5);
        require(f, 501);
        uint256 addr = cfg5.toSlice().loadUnsigned(256);
        require(msg.sender == address.makeAddrStd(-1, addr), 502);
        _;
    }

    function change_public_key(uint256 public_key) public internalMsg requireOwnerContract {
        tvm.accept();
        tvm.setPubkey(public_key);
    }

    function change_config_param(uint32 index, TvmCell data) public internalMsg requireOwnerContract {
        require(data.toSlice().depth() <= 128, 39);

        tvm.accept();
        m_cfg_dict[index] = data;
    }

    function change_elector_code(TvmCell code, TvmCell data) public internalMsg pure requireOwnerContract {
        require(code.depth() <= 128, 39);
        require(data.depth() <= 128, 39);
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        if (!f) {
            return;
        }
        tvm.accept();
        uint256 elector_addr = cfg1.toSlice().loadUnsigned(256);
        uint32 query_id = now;
        IElector(address.makeAddrStd(-1, elector_addr))
            .upgrade_code{value: 1 << 30, flag: 0}(query_id, code, data);
    }

    function change_code(TvmCell code) public internalMsg requireOwnerContract {
        require(code.depth() <= 128, 39);
        tvm.setcode(code);
        onCodeUpgrade();
    }

    function setcode_confirmation(uint64 query_id, uint32 body) override
        functionID(0xce436f64) public {
    }

    onTickTock(bool /* is_tock */) external {
        optional(TvmCell) c = m_cfg_dict.fetch(36);
        bool updated = false;
        if (c.hasValue()) {
            // check whether we have to set next_vset as the current validator set
            TvmCell next_vset = c.get();
            TvmSlice ds = next_vset.toSlice();
            if (ds.bits() >= 40) {
                (uint8 tag, uint32 since) = ds.decode(uint8, uint32);
                if ((since <= now) && (tag == 0x12)) {
                    // next validator set becomes active!
                    optional(TvmCell) cur_vset = m_cfg_dict.getSet(34, next_vset);
                    m_cfg_dict.getSet(32, cur_vset.get());
                    delete m_cfg_dict[36];
                    updated = true;
                }
            }
        }
        if (!updated) {
            c = m_cfg_dict.fetch(35);
            if (c.hasValue()) {
                TvmCell slashed_vset = c.get();
                TvmSlice ds = slashed_vset.toSlice();
                if (ds.bits() >= 40) {
                    (uint8 tag, uint32 since) = ds.decode(uint8, uint32);
                    if ((since <= now) && (tag == 0x12)) {
                        m_cfg_dict.getSet(34, slashed_vset);
                        delete m_cfg_dict[35];
                        updated = true;
                    }
                }
            }
        }
        if (!updated) {
            // if nothing has been done so far, scan a random voting proposal instead
            //scan_random_proposal(); TODO
        }
    }

    onBounce(TvmSlice slice) external {
    }

    receive() external {
    }

    function reset_utime_until() public {
        tvm.accept();
        TvmCell c = m_cfg_dict[34];
        Common.ValidatorSet vset = c.toSlice().decode(Common.ValidatorSet);
        vset.utime_until = now;
        TvmBuilder b;
        b.store(vset);
        m_cfg_dict[34] = b.toCell();
        // delete next vset to force announce_new_elections
        delete m_cfg_dict[36];
    }

    // ts4 helpers
    function get_config_0()  public returns (TvmCell) {
        TvmBuilder b;
        b.store(address(this).value);
        m_cfg_dict[0] = b.toCell();
        return m_cfg_dict[0];
    }
    function get_config_1()  public view returns (TvmCell) {
        return m_cfg_dict[1];
    }
    function get_config_13() public view returns (TvmCell) {
        return m_cfg_dict[13];
    }
    function get_config_15() public view returns (TvmCell) {
        return m_cfg_dict[15];
    }
    function get_config_16() public view returns (TvmCell) {
        return m_cfg_dict[16];
    }
    function get_config_17() public view returns (TvmCell) {
        return m_cfg_dict[17];
    }
    function get_config_32() public view returns (TvmCell) {
        return m_cfg_dict[32];
    }
    function get_config_34() public view returns (TvmCell) {
        return m_cfg_dict[34];
    }
    function get_config_35() public view returns (TvmCell) {
        return m_cfg_dict[35];
    }
    function get_config_36() public view returns (TvmCell) {
        return m_cfg_dict[36];
    }
    function get_config(uint32 index) public returns (TvmCell) {
        if (index == 0) {
            get_config_0();
        } else {
            return m_cfg_dict[index];
        }
    }

    function get_vset(uint32 id) private view returns (__ValidatorSet) {
        optional(TvmCell) c = m_cfg_dict.fetch(id);
        if (c.hasValue()) {
            __ValidatorSet vset = c.get().toSlice().decode(__ValidatorSet);
            return vset;
        } else {
            __ValidatorSet vset;
            return vset;
        }
    }

    // Get previous validator set in a structured form
    function get_previous_vset() public view returns (__ValidatorSet) {
        return get_vset(32);
    }

    // Get current validator set in a structured form
    function get_current_vset() public view returns (__ValidatorSet) {
        return get_vset(34);
    }

    // Get current slashed validator set in a structured form
    function get_slashed_vset() public view returns (__ValidatorSet) {
        return get_vset(35);
    }

    // Get next validator set in a structured form
    function get_next_vset() public view returns (__ValidatorSet) {
        return get_vset(36);
    }

    function public_key() public view returns (uint256) {
        return tvm.pubkey();
    }

    function onCodeUpgrade() private functionID(2) {
        // old funC code upgrade
        require(tvm.hash(tvm.code()) == 0xbac24be401b3489f90018d08137c4063f24bfc6def86a61836060d6dbc32e703, 550);
        {
            tvm.resetStorage();
            tvm.setReplayProtTime(now);
            TvmSlice cs = tvm.getData().toSlice();
            uint256 pubkey;
            TvmCell cfg_dict_root;
            uint32 _seqno;
            (cfg_dict_root, _seqno, pubkey, ) = cs.decode(
                TvmCell, uint32, uint256, mapping(uint32 => TvmCell)
            );
            TvmBuilder b;
            b.store(true, cfg_dict_root);
            m_cfg_dict = b.toSlice().decode(mapping(uint32 => TvmCell));
            tvm.setPubkey(pubkey);
        }
        tvm.exit();
    }

    function upgrade_code(TvmCell code) override public externalMsg {
        require(tvm.pubkey() != 0, 101);
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        tvm.setcode(code);
        onCodeUpgrade();
    }

    // dummy for tests
    function seqno() public pure returns (uint32) {}

    function upgrade_old_config_code_sign_helper(uint32 msg_seqno, uint32 valid_until, TvmCell code)
            public pure returns (TvmCell) {
        TvmBuilder b;
        b.storeUnsigned(0x4e436f64, 32);
        b.store(msg_seqno);
        b.store(valid_until);
        b.store(code);
        uint256 hash = tvm.hash(b.toCell());
        TvmBuilder b1;
        b1.store(hash);
        return b1.toCell();
    }

    function upgrade_old_config_code_message_builder(bytes signature, uint32 msg_seqno, uint32 valid_until, TvmCell code)
            public pure returns (TvmCell) {
        (TvmCell cfg0, ) = tvm.rawConfigParam(0);
        uint256 config_addr = cfg0.toSlice().loadUnsigned(256);
        address dst = address.makeAddrStd(-1, config_addr);

        TvmBuilder builder;
        builder.storeUnsigned(2, 2);        // ext_in_msg_info$0 - constant value
        builder.storeUnsigned(0, 2);        // src:MsgAddress we store addr_none$00
        // Function store() allows to store variable of arbitrary type in the builder.
        builder.store(dst);                 // dest:MsgAddressInt

        builder.storeUnsigned(0, 4);        // import_fee::Grams

        builder.storeUnsigned(0, 1);        // init:(Maybe (Either StateInit ^StateInit)) - we store 0, because we don't attach
                                            // initial state of a contract.

        builder.storeUnsigned(1, 1);        // body:(Either X ^X) - we store one, because body of the message is stored in the
                                            // reference of current cell.

        TvmBuilder b;
        b.store(signature.toSlice());
        b.storeUnsigned(0x4e436f64, 32);
        b.store(msg_seqno);
        b.store(valid_until);
        b.store(code);
        builder.storeRef(b);

        return builder.toCell();
    }
}
