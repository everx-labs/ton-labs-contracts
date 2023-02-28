/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;
import "IValidator.sol";
import "IElector.sol";

contract Validator is IValidator {

    bool m_defunct;

    constructor(uint256 pubkey) public {
        tvm.accept();
        tvm.setPubkey(pubkey);
        m_defunct = false;
    }

    function stake(uint64 query_id, uint256 validator_pubkey, uint32 stake_at,
                   uint32 max_factor, uint256 adnl_addr, uint128 value,
                   bytes signature) public pure
    {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 123);
        tvm.accept();
        address elector = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));

        IElector(elector).process_new_stake{value: value}(
            query_id, validator_pubkey, stake_at, max_factor, adnl_addr,
            signature);
    }

    function stake_sign_helper(uint32 stake_at, uint32 max_factor, uint256 adnl_addr)
            public pure returns (TvmCell) {
        TvmBuilder b;
        b.storeUnsigned(0x654c5074, 32);
        b.store(stake_at);
        b.store(max_factor);
        b.store(address(this).value);
        b.store(adnl_addr);
        return b.toCell();
    }

    uint64 m_returned_query_id;
    uint32 m_returned_body;

    function return_stake(uint64 query_id, uint32 body) override functionID(0xee6f454c) public {
        m_returned_query_id = query_id;
        m_returned_body = body;
    }

    uint64 m_confirmed_query_id;
    uint32 m_confirmed_body;

    function confirmation(uint64 query_id, uint32 body) override functionID(0xf374484c) public {
        m_confirmed_query_id = query_id;
        m_confirmed_body     = body;
    }

    function get() public view returns (uint64 confirmed_query_id, uint32 confirmed_body,
                                        uint64 returned_query_id, uint32 returned_body,
                                        uint64 refund_query_id,
                                        uint64 error_query_id, uint32 error_body,
                                        mapping(uint64 => int8) complain_answers) {
        confirmed_query_id = m_confirmed_query_id;
        confirmed_body     = m_confirmed_body;
        returned_query_id  = m_returned_query_id;
        returned_body      = m_returned_body;
        refund_query_id    = m_refund_query_id;
        error_query_id     = m_error_query_id;
        error_body         = m_error_body;
        complain_answers   = m_complain_answers;
    }

    function recover(uint64 query_id, uint128 value) public pure {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 123);
        tvm.accept();
        address elector = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));

        IElector(elector).recover_stake{value: value}(query_id);
    }

    uint64 m_refund_query_id;

    function toggle_defunct() public {
        tvm.accept();
        m_defunct = !m_defunct;
    }

    function receive_stake_back(uint64 query_id) override functionID(0xf96f7324) public {
        require(!m_defunct, 177);
        tvm.accept();
        m_refund_query_id = query_id;
    }

    uint64 m_error_query_id;
    uint32 m_error_body;

    function error(uint64 query_id, uint32 body) override public {
        m_error_query_id = query_id;
        m_error_body     = body;
    }

    mapping(uint64 => int8) m_complain_answers;

    fallback() external {
        TvmSlice payload = msg.data;
        uint32 function_id = payload.decode(uint32);
        if (function_id == 0xfffffffe) {
            (uint64 query_id, uint32 body) = payload.decode(uint64, uint32);
            error(query_id, body);
            tvm.commit();
            return;
        }
        if ((0xf2676350 <= function_id) && (function_id <= 0xf2676359)) {
            // answer from register_complaint
            (uint64 query_id, uint32 body) = payload.decode(uint64, uint32);
            require(body == 0x52674370, 101);
            m_complain_answers[query_id] = int8(function_id - 0xf2676350);
            tvm.commit();
            return;
        }
        if ((0xd674523d <= function_id) && (function_id <= 0xd6745242)) {
            // answer from proceed_register_vote
            (uint64 query_id, uint32 body) = payload.decode(uint64, uint32);
            require(body == 0x56744370, 102);
            m_complain_answers[query_id] = int8(function_id - 0xd6745240);
            tvm.commit();
            return;
        }
        require(false, 103);
    }

    function send_complaint(address addr, uint128 value, TvmCell payload) internal pure {
        TvmBuilder b;
        b.storeUnsigned(0x18, 6);
        b.store(addr);
        b.storeTons(value);
        b.storeUnsigned(0, 1 + 4 + 4 + 64 + 32 + 1);
        b.storeUnsigned(1, 1);
        b.store(payload);
        tvm.sendrawmsg(b.toCell(), 0);
    }

    function complain(uint64 query_id, uint32 election_id, uint256 validator_pubkey,
                      uint128 value, uint128 suggested_fine) public pure {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 100);
        tvm.accept();
        address elector_addr = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));

        TvmBuilder b;
        b.store(uint32(0x52674370)); // register_complaint function id
        b.store(query_id, election_id);
        b.store(uint8(0xbc), validator_pubkey);
        TvmBuilder b2;
        b2.store(uint256(0x416e20656d707479206465736372697074696f6e2e));
        b.store(b2.toCell());
        b.store(uint32(0));
        b.store(uint8(0));
        b.storeUnsigned(0, 256);
        b.storeTons(0);
        b.storeTons(suggested_fine);
        b.store(uint32(0));
        send_complaint(elector_addr, value, b.toCell());
    }

    function vote(uint64 query_id, uint256 signature_hi, uint256 signature_lo,
                  uint16 idx, uint32 elect_id, uint256 chash) public pure {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 100);
        tvm.accept();
        address elector_addr = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));

        IElector(elector_addr).proceed_register_vote{value: 0}(query_id, signature_hi,
            signature_lo, 0x56744350, idx, elect_id, chash);
    }

    function vote_sign_helper(uint16 idx, uint32 elect_id, uint256 chash)
            public pure returns (TvmCell) {
        TvmBuilder b;
        b.storeUnsigned(0x56744350, 32);
        b.store(idx);
        b.store(elect_id);
        b.store(chash);
        return b.toCell();
    }

    function report_sign_helper(uint256 reporter_pubkey, uint256 victim_pubkey, uint8 metric_id)
            public pure returns (TvmCell) {
        TvmBuilder b;
        b.store(reporter_pubkey, victim_pubkey, metric_id);
        return b.toCell();
    }

    function transfer(uint128 value) public pure {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 123);
        tvm.accept();
        address elector = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));
        elector.transfer(value);
    }

    function transfer_to_config(TvmCell payload) public pure {
        (TvmCell cfg0, bool f) = tvm.rawConfigParam(0);
        require(f, 123);
        tvm.accept();
        address config = address.makeAddrStd(-1, cfg0.toSlice().loadUnsigned(256));
        config.transfer(1 << 30, false, 0, payload);
    }

    function receive_elect_at(uint64 query_id, bool election_open, uint32 elect_at) override
            functionID(0xf8229612) external
    {
        query_id = query_id; // to suspend warning
        election_open = election_open;
        elect_at = elect_at;
    }

    receive() external view {
    }

    function public_key() public view returns (uint256) {
        return tvm.pubkey();
    }

}
