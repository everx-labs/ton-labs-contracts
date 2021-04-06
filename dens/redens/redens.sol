pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

contract Redens {
    uint256 static public codeHash;
    uint256 public authorKey;

    constructor(uint256 pubkey) public {
        require(msg.pubkey() == pubkey, 100);
        tvm.accept();
        authorKey = pubkey;
    }

    function upgrade(TvmCell state) public virtual {
        require(msg.pubkey() == authorKey, 100);
        TvmCell newcode = state.toSlice().loadRef();
        tvm.accept();
        tvm.commit();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
        onCodeUpgrade();
    }

    function onCodeUpgrade() internal {
        tvm.resetStorage();
    }
}