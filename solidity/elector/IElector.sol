/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;

interface IElector {
    /// @dev Allows validator to become validator candidate
    function process_new_stake(
        uint64 query_id,
        uint256 validator_key,
        uint32 stake_at,
        uint32 max_factor,
        uint256 adnl_addr,
        bytes signature
    ) external functionID(0x4E73744B) internalMsg;

    /// @dev Allows getting back validator's stake
    function recover_stake(uint64 query_id) external functionID(0x47657424) internalMsg;
    function recover_stake_gracefully(uint64 query_id, uint32 elect_id) external functionID(0x47657425) internalMsg;

    /// @dev Allow getting elector info
    function get_elect_at(uint64 query_id) external functionID(0x47657426) internalMsg;

    /// @dev Confirmation from configuration smart contract
    function config_set_confirmed_ok(uint64 query_id) external functionID(0xee764f4b) internalMsg;
    function config_set_confirmed_err(uint64 query_id) external functionID(0xee764f6f) internalMsg;

    function config_slash_confirmed_ok(uint64 query_id) external functionID(0xee764f4c) internalMsg;
    function config_slash_confirmed_err(uint64 query_id) external functionID(0xee764f70) internalMsg;

    /// @dev Upgrade code (is accepted only from configuration smart contract)
    function upgrade_code(uint64 query_id, TvmCell code, TvmCell data) external functionID(0x4e436f64) internalMsg;

    struct Complaint {
        uint8 tag; // = 0xbc
        uint256 validator_pubkey;
        TvmCell description;
        uint32 created_at;
        uint8 severity;
        uint256 reward_addr;
        uint128 paid;           // TODO varuint16 for funC compatibility
        uint128 suggested_fine; // TODO
        uint32 suggested_fine_part;
    }

    /// @dev Register new complaint
    //function register_complaint(
    //    uint64 query_id,
    //    uint32 election_id,
    //    Complaint complaint
    //) external functionID(0x52674370);

    /// @dev Vote for a complaint
    function proceed_register_vote(
        uint64 query_id,
        uint256 signature_hi,
        uint256 signature_lo,
        uint32 sign_tag,
        uint16 idx,
        uint32 elect_id,
        uint256 chash
    ) external functionID(0x56744370) internalMsg;

    function grant() external functionID(0x4772616e) internalMsg;
    function take_change() external internalMsg;
}
