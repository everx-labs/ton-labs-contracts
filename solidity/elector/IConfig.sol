/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;

interface IConfig {
  
    function set_next_validator_set(uint64 query_id, TvmCell vset)
        functionID(0x4e565354) external;

    function set_slashed_validator_set(uint64 query_id, TvmCell vset)
        functionID(0x4e565355) external;

    function set_code(TvmCell code) external externalMsg;

    function setcode_confirmation(uint64 query_id, uint32 body)
        functionID(0xce436f64) external;

}
