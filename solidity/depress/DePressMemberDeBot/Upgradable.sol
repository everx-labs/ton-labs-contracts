pragma ton-solidity ^0.35.0;

abstract contract Upgradable {
    /*
     * Set code
     */

    function upgrade(TvmCell state) public virtual {
        require(msg.pubkey() == tvm.pubkey(), 100);
        TvmCell newcode = state.toSlice().loadRef();
        tvm.accept();
        tvm.commit();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
        onCodeUpgrade();
    }

    function onCodeUpgrade() internal virtual;
}