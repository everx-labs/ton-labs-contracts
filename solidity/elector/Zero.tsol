/*
    This file is part of TON OS.

    TON OS is free software: you can redistribute it and/or modify 
    it under the terms of the Apache License 2.0 (http://www.apache.org/licenses/)

    Copyright 2019-2023 (c) EverX
*/

pragma ton-solidity ^ 0.66.0;
import "IElector.sol";

contract Zero {

    function grant(uint128 value) public pure {
        (TvmCell cfg1, bool f) = tvm.rawConfigParam(1);
        require(f, 123);
        address elector = address.makeAddrStd(-1, cfg1.toSlice().loadUnsigned(256));
        tvm.accept();
        elector.transfer(value);
    }

}
