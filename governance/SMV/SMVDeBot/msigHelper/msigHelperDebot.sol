pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

interface IMultisig {
    function submitTransaction(
        address dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload)
    external returns (uint64 transId);

    function sendTransaction(
        address dest,
        uint128 value,
        bool bounce,
        uint8 flags,
        TvmCell payload) external;
}

contract MultisigHelperDebot is Debot, DError {
    
    // helper modifier
    modifier accept() {
        tvm.accept();
        _;
    }

    /*
     *   Init functions
     */

    constructor(uint8 options, string debotAbi, string targetAbi, address targetAddr) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        init(options, debotAbi, targetAbi, targetAddr);
    }

    function setABI(string dabi) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        m_debotAbi.set(dabi);
        m_options |= DEBOT_ABI;
    }

    function setTargetABI(string tabi) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        m_targetAbi.set(tabi);
        m_options |= DEBOT_TARGET_ABI;
    }

    /*
     *  Overrided Debot functions
     */

    function fetch() public override accept returns (Context[] contexts) {
		// Zero state: work with existing wallet or deploy new one.
        contexts.push(Context(STATE_ZERO, 
            "Hello, I'm a Multisig Helper Debot. I'm created to be invoked! Have a nice day!", [
            ActionPrint("Quit", "quit", STATE_EXIT) ] ));

    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Multisig Helper DeBot";
        semver = (1 << 8) | 0;
    }

    function quit() public override accept { }

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        return "unknown exception! Code: "+string(error);
    }

    /*
     *  Send message handlers
     */

    function sendSendTransactionEx(TvmCell misc) public accept pure returns (address dest, TvmCell body) {
        (address wallet, address recipient, uint64 amount, uint8 bounce, uint8 flags, TvmCell payload) = 
            misc.toSlice().decode(address, address, uint64, uint8, uint8, TvmCell);
        dest = wallet;
        body = tvm.encodeBody(IMultisig.sendTransaction, 
            recipient, amount, 
            bounce == 1 ? true : false,
            flags,
            payload
        );
    }

    function sendSubmitMsgEx(TvmCell misc) public accept pure returns (address dest, TvmCell body) {
        (address wallet, address recipient, uint64 amount, uint8 bounce, uint8 allBalance, TvmCell payload) = 
            misc.toSlice().decode(address, address, uint64, uint8, uint8, TvmCell);
        dest = wallet;
        body = tvm.encodeBody(IMultisig.submitTransaction, 
            recipient, amount, 
            bounce == 1 ? true : false,
            allBalance == 1 ? true : false,
            payload
        );
    }

}
