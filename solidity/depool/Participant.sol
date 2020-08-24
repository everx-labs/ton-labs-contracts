// 2020 (c) TON Venture Studio Ltd

pragma solidity >0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "DePoolLib.sol";

contract Participant {
    function sendTransaction(
        address dest,
        uint64 value,
        bool bounce,
        uint16 flags,
        TvmCell payload) public view
    {
        require(msg.pubkey() == tvm.pubkey(), Errors.IS_NOT_OWNER);
        tvm.accept();
        dest.transfer(value, bounce, flags, payload);
    }

    receive() external virtual {}
    fallback() external virtual {}
}