pragma ton-solidity ^0.51.0;
pragma AbiHeader expire;

contract BurnerDeployer {

    modifier checkOwnerAndAccept {
        require(msg.pubkey() == tvm.pubkey(), 102);
        tvm.accept();
        _;
    }

    function deploy() public checkOwnerAndAccept pure returns (address addr) {
        TvmBuilder b;
        // _ split_depth:(Maybe (## 5)) special:(Maybe TickTock)
        //    code:(Maybe ^Cell) data:(Maybe ^Cell)
        //   library:(Maybe ^Cell) = StateInit;
        b.store(false, false, false, false, false);
        TvmCell stateInit = b.toCell();
        addr = address.makeAddrStd(0, tvm.hash(stateInit));
        addr.transfer({value: 0.01 ton, bounce: false, stateInit: stateInit});
    }
}