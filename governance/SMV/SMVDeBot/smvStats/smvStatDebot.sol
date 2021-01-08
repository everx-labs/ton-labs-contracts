pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

contract SMVStatDebot is Debot, DError {

    struct TransferInfo {
      uint256 proposalId;
      address contestAddr;
      uint256 requestValue;
    }

    TransferInfo[] m_Transfers;

    /*
     *   Helper modifiers
     */

    modifier onlyOwnerAccept() {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        _;
    }

    modifier accept() {
        tvm.accept();
        _;
    }

    /*
     *   Init functions
     */

    constructor(uint8 options, string debotAbi, string targetAbi, address targetAddr) public onlyOwnerAccept {
        init(options, debotAbi, targetAbi, targetAddr);
    }
    
    function setABI(string dabi) public onlyOwnerAccept {
        m_debotAbi.set(dabi);
        m_options |= DEBOT_ABI;
    }

    function setTargetABI(string tabi) public onlyOwnerAccept {
        m_targetAbi.set(tabi);
        m_options |= DEBOT_TARGET_ABI;
    }

     /*
     *   Derived Debot Functions
     */

    function fetch() public override accept returns (Context[] contexts) {
 	
        optional(string) empty;

        contexts.push(Context(STATE_ZERO,
		    "", [   
            ActionGetMethod("querying smv stat...", "getTransfers", empty, 
            "setTransfers", true, STATE_CURRENT),
            ActionInstantRun("", "fetchTransfers", STATE_CURRENT),
            ActionGoto("Return to main", STATE_EXIT) ] ));

    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "SMV Statistic DeBot";
        semver = (0 << 8) | 1;
    }

    function quit() public override accept {}

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        return "unknown exception";
    }

    /*
     *   Handlers
     */

     function setTransfers(TransferInfo[] value0) public accept {
       m_Transfers = value0;
     }

    function fetchTransfers() public accept returns (Action[] actions) {
        for(uint256 i = 0; i < m_Transfers.length; i++) {
            Action act = ActionPrint("", "Transfer:\n proposal id: {}\n contest address: {}\n request value (ton): {}.{}", STATE_CURRENT);
            act.attrs = "instant,fargs=parseTransfer";
            TvmBuilder ctx;
            ctx.store(m_Transfers[i].proposalId,m_Transfers[i].contestAddr,m_Transfers[i].requestValue);
            act.misc = ctx.toCell();
            actions.push(act);
        }
    }

    function parseTransfer(TvmCell misc) public accept returns (uint256 number0, address param1, uint64 number2, uint64 number3) {
        uint256 t;
        (number0,param1,t) = misc.toSlice().decode(uint256,address,uint256);
        (number2, number3) = tokens(t);
    }

    function tokens(uint256 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    } 

}
