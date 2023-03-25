/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2023 (c) EverX
*/

pragma ton-solidity ^ 0.67.0;
pragma AbiHeader expire;
pragma AbiHeader time;
import "IConfig.sol";
import "IElector.sol";
import "Common.sol";

contract Config is IConfig {

    uint32 constant VERSION_MAJOR = 0;
    uint32 constant VERSION_MINOR = 1;

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
            tvm.accept();
            // message from elector smart contract
            // set next validator set
            (uint32 t_since, uint32 t_until) = check_validator_set(vset);
            ok = (t_since > block.timestamp) && (t_until > t_since);
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
            tvm.accept();
            // message from elector smart contract
            // set slashed validator set
            (uint32 t_since, uint32 t_until) = check_validator_set(vset);
            ok = (t_since > block.timestamp) && (t_until > t_since);
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

    function set_public_key(uint256 pubkey) public externalMsg requireOwner {
        tvm.accept();
        tvm.setPubkey(pubkey);
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
        uint32 query_id = block.timestamp;
        IElector(address.makeAddrStd(-1, elector_addr))
            .upgrade_code{value: 1 << 30, flag: 0}(query_id, code, data);
    }

    function set_code(TvmCell code) override public externalMsg requireOwner {
        require(code.depth() <= 128, 39);
        tvm.setcode(code);
        tvm.setCurrentCode(code);
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

    function change_public_key(uint256 pubkey) public internalMsg requireOwnerContract {
        tvm.accept();
        tvm.setPubkey(pubkey);
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
        uint32 query_id = block.timestamp;
        IElector(address.makeAddrStd(-1, elector_addr))
            .upgrade_code{value: 1 << 30, flag: 0}(query_id, code, data);
    }

    function change_code(TvmCell code) public internalMsg pure requireOwnerContract {
        require(code.depth() <= 128, 39);
        tvm.setcode(code);
        tvm.setCurrentCode(code);
        onCodeUpgrade();
    }

    function onCodeUpgrade() private pure functionID(2) {
        tvm.accept();
        tvm.exit();
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
                if ((since <= block.timestamp) && (tag == 0x12)) {
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
                    if ((since <= block.timestamp) && (tag == 0x12)) {
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
        vset.utime_until = block.timestamp;
        TvmBuilder b;
        b.store(vset);
        m_cfg_dict[34] = b.toCell();
        // delete next vset to force announce_new_elections
        delete m_cfg_dict[36];
    }

    function get_config_param(uint32 index) public view returns (TvmCell) {
        return m_cfg_dict[index];
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

    // returns version of elector (major, minor)
    function get_version() public pure returns (uint32, uint32) {
        return (VERSION_MAJOR, VERSION_MINOR);
    }
}