pragma ton-solidity ^0.35.0;

abstract contract Transferable {
    function transfer(address dest, uint128 value, bool bounce, uint16 flags) public view {
        require(msg.pubkey() == tvm.pubkey(), 100);
        tvm.accept();
        dest.transfer(value, bounce, flags);
    }
}