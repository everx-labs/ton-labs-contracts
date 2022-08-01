/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2021 (c) TON LABS
*/

pragma ton-solidity >=0.38.0;

interface IValidator {

    function return_stake(uint64 query_id, uint32 body) functionID(0xee6f454c) external;
    function confirmation(uint64 query_id, uint32 body) functionID(0xf374484c) external;
    function receive_stake_back(uint64 query_id) functionID(0xf96f7324) external;
    function receive_elect_at(uint64 query_id, bool election_open, uint32 elect_at) functionID(0xf8229612) external;
    function error(uint64 query_id, uint32 body) /* functionID(0xfffffffe) */ external;

}
