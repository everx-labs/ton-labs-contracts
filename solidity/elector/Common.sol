/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;

library Common {

    struct Validator {
        uint8 tag; // = 0x53
        uint32 ed25519_pubkey; // = 0x8e81278a
        uint256 pubkey;
        uint64 weight;
    }

    struct ValidatorAddr {
        uint8 tag; // = 0x73
        uint32 ed25519_pubkey; // = 0x8e81278a
        uint256 pubkey;
        uint64 weight;
        uint256 adnl_addr;
        uint256 bls_key1;
        uint128 bls_key2;
    }

    struct ValidatorSet { // config params 32, 34, 36
        uint8 tag; // = 0x12
        uint32 utime_since;
        uint32 utime_until;
        uint16 total;
        uint16 main;
        uint64 total_weight;
        mapping(uint16 => TvmSlice /* Validator or ValidatorAddr */) vdict;
    }

}
