pragma ton-solidity >=0.40.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "../Upgradable.sol";

contract Redens is Upgradable {
    uint256 static public codeHash;

    constructor(uint256 pubkey) public {
        require(msg.pubkey() == pubkey, 100);
        tvm.accept();
        tvm.setPubkey(pubkey);
    }

    function getAuthorKey() public view returns (uint256 authorKey) {
        authorKey = tvm.pubkey();
    }

    function onCodeUpgrade() internal override {
        tvm.resetStorage();
    }
}