pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

contract ProposalRootDebot is Debot, DError {

    /*
     * Context ids
     */
    uint8 constant STATE_PROPOSAL_INFO              = 1;
    uint8 constant SHOW_WHITELIST                   = 2; 

    struct ProposalInfo{
      uint256 id;
      uint32 start;
      uint32 end;
      bytes desc;
      bool finished;
      bool approved;
      bool resultsSent;
      bool earlyFinished;
      bool whiteListEnabled;
      uint128 totalVotes;
      uint128 currentVotes;
      uint128 yesVotes;
      uint128 noVotes;
      uint256 votePrice;
    }

    ProposalInfo m_ProposalInfo;
    uint256[] m_whitelistkeys;
   
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
		    "Please enter proposal address:", [ //TODO check proposal code hash            
            ActionInstantRun("", "enterProposalAddress", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_PROPOSAL_INFO), "instant") ] ));

        contexts.push(Context(STATE_PROPOSAL_INFO,
		    "", [   
            ActionGetMethod("querying proposal info...", "getProposal", empty, 
            "setProposalInfo", true, STATE_CURRENT),
            ActionInstantRun("", "fetchProposalInfo", STATE_CURRENT),
            ActionGoto("Return to main", STATE_EXIT) ] ));

        contexts.push(Context(SHOW_WHITELIST,
		    "", [   
            ActionGetMethod("querying whitelist...", "getWhiteList", empty, 
            "setProposalWhitelist", true, STATE_CURRENT),
            ActionInstantRun("", "fetchProposalWhitelist", STATE_CURRENT),
            ActionGoto("Return to main", STATE_EXIT) ] ));

    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Proposal DeBot";
        semver = (0 << 8) | 1;
    }

    function quit() public override accept {}

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        return "unknown exception";
    }

    /*
     *   Handlers
     */

    function enterProposalAddress(address adr) public accept {        
        m_target.set(adr);
        m_options |= DEBOT_TARGET_ADDR;
    }

     function setProposalWhitelist(uint256[] value0) public accept {
       m_whitelistkeys = value0;
     }

    function fetchProposalWhitelist() public accept returns (Action[] actions) {
        for(uint256 i = 0; i < m_whitelistkeys.length; i++) {
            Action act = ActionPrint("", "{}", STATE_CURRENT);
            act.attrs = "instant,fargs=parseProposalWhitelist";
            TvmBuilder ctx;
            ctx.store(m_whitelistkeys[i]);
            act.misc = ctx.toCell();
            actions.push(act);
        }
    }

    function parseProposalWhitelist(TvmCell misc) public accept returns (uint256 param0) {
        (param0) = misc.toSlice().decode(uint256);
    }


     /*proposal info*/

    function setProposalInfo(uint256 id,uint32 start,uint32 end,bytes desc,bool finished, bool approved,bool resultsSent,bool earlyFinished,
        bool whiteListEnabled, uint128 totalVotes, uint128 currentVotes, uint128 yesVotes, uint128 noVotes,uint256 votePrice) public accept {
        m_ProposalInfo.id = id;
        m_ProposalInfo.start = start;
        m_ProposalInfo.end = end;
        m_ProposalInfo.desc = desc;
        m_ProposalInfo.finished = finished;
        m_ProposalInfo.approved = approved;
        m_ProposalInfo.resultsSent = resultsSent;
        m_ProposalInfo.earlyFinished = earlyFinished;
        m_ProposalInfo.whiteListEnabled = whiteListEnabled;
        m_ProposalInfo.totalVotes = totalVotes;
        m_ProposalInfo.currentVotes = currentVotes;
        m_ProposalInfo.yesVotes = yesVotes;
        m_ProposalInfo.noVotes = noVotes;
        m_ProposalInfo.votePrice = votePrice;
      }     

    function fetchProposalInfo() public accept returns (Action[] actions) {        
        Action act = ActionPrint("", "Proposal info:\n id: {}\n start time: {}\n end time: {}\n description: {}\n finished: {}\n approved: {}\n early finished: {}\n whitelist enabled: {}\n total votes: {}\n current votes: {}\n yes votes: {}\n no votes: {}\n vote price (ton): {}.{}\n", STATE_CURRENT);
        act.attrs = "instant,fargs=parseMultiBallotAddress";
        actions.push(act);
        if (m_ProposalInfo.whiteListEnabled) actions.push(ActionGoto("Show whitelist keys", SHOW_WHITELIST));
    }

    function parseMultiBallotAddress() public accept returns (uint256 number0,uint32 utime1,uint32 utime2, string str3,
        string str4, string str5, string str6, string str7, uint128 number8, uint128 number9, uint128 number10, uint128 number11,
        uint256 number12, uint256 number13
    ) {
        number0 = m_ProposalInfo.id;
        utime1 = m_ProposalInfo.start;
        utime2 = m_ProposalInfo.end;
        str3 = m_ProposalInfo.desc;
        str4 =  m_ProposalInfo.finished ? "true" : "false";
        str5 =  m_ProposalInfo.approved ? "true" : "false";
        str6 =  m_ProposalInfo.earlyFinished ? "true" : "false";
        str7 =  m_ProposalInfo.whiteListEnabled ? "true" : "false";
        number8 = m_ProposalInfo.totalVotes;
        number9 = m_ProposalInfo.currentVotes;
        number10 = m_ProposalInfo.yesVotes;
        number11 = m_ProposalInfo.noVotes;
        (number12, number13) = tokens(m_ProposalInfo.votePrice);
    }

    function tokens(uint256 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    } 

}
