pragma ton-solidity ^0.51.0;
pragma AbiHeader expire;

contract BurnerDeployer {

    modifier checkOwnerAndAccept {
        require(msg.pubkey() == tvm.pubkey(), 102);
        tvm.accept();
        _;
    }

    function deploy() public checkOwnerAndAccept pure returns (address addr) {
        TvmBuilder code;
        code.storeUnsigned(0xFF00, 16); // SETCP0
        code.storeUnsigned(0, 8); // NOP
        TvmBuilder b;
        // _ split_depth:(Maybe (## 5)) special:(Maybe TickTock)
        //    code:(Maybe ^Cell) data:(Maybe ^Cell)
        //   library:(Maybe ^Cell) = StateInit;
        b.store(false, false, true, code.toCell(), false, false);
        TvmCell stateInit = b.toCell();
        addr = address.makeAddrStd(-1, tvm.hash(stateInit));
        addr.transfer({value: 0.1 ton, bounce: false, stateInit: stateInit});
    }
}