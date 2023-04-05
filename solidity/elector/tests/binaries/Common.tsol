/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2023 (c) EverX
*/

pragma ton-solidity ^ 0.66.0;

library Common {
    enum ValidatorSetType {
        PREVIOUS,
        CURRENT,
        SLASHED,
        NEXT
    }
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
    }

    struct ValidatorSet { // config params 32, 34, 36
        uint8 tag; // = 0x12
        uint32 utime_since;
        uint32 utime_until;
        uint16 total;
        uint64 total_weight;
        mapping(uint16 => TvmSlice /* Validator or ValidatorAddr */) vdict;
    }

    struct ValidatorSets {
        optional(ValidatorSet) previous; //32
        optional(ValidatorSet) current; // 34
        optional(ValidatorSet) slashed; // 35
        optional(ValidatorSet) next;   // 36
    }

    function getValidatorSets() internal returns (optional(mapping(int32 => Common.ValidatorSets))) {
        (TvmCell cfg100, bool f1) = tvm.rawConfigParam(100);
        (optional(mapping(int32 => Common.ValidatorSets)) vsets) = cfg100.toSlice().decodeQ(mapping(int32 => Common.ValidatorSets));
        return vsets;
    }

    function validatorSetsToCell(mapping(int32 => Common.ValidatorSets) vsets) internal pure returns (TvmCell) {
        TvmBuilder b;
        b.store(vsets);
        return b.toCell();
    }

    function validatorSetFromCell(TvmCell vset) internal pure returns(Common.ValidatorSet) {
       return vset.toSlice().decode(Common.ValidatorSet);
    }

    function validatorSetToCell(Common.ValidatorSet vset) internal pure returns (TvmCell) {
        TvmBuilder b;
        b.store(vset);
        return b.toCell();
    }

    function getValidatorSetsByChain(int32 chainId) internal returns (optional(Common.ValidatorSets)) {
        optional(mapping(int32 => Common.ValidatorSets)) may_be_vsets = getValidatorSets();
        if (may_be_vsets.hasValue() && may_be_vsets.get().exists(chainId)) {
            return may_be_vsets.get()[chainId];
        }
        optional(Common.ValidatorSets) dummy;
        return dummy;
    }

}
