pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

abstract contract AContest {
   constructor(bytes title, bytes link, uint256 hash, address juryAddr,
               uint256[] juryKeys, uint64 startsIn, uint64 lastsFor, uint64 votingWindow,
               uint256 sendApprovalGrams) public functionID(0x309) {}
}

interface ISuperRoot {
    function createProposal(uint256 id, uint128 totalVotes,
    uint32 startime,uint32 endtime,bytes desc,bool superMajority,uint256 votePrice,bool finalMsgEnabled, TvmCell finalMsg, uint256 finalMsgValue,
    uint256 finalMsgRequestValue, bool whiteListEnabled, uint256[] whitePubkeys) external returns(bool value0);
}

contract DeployProposalDebot is Debot, DError {

    /*
     * Context ids
     */
    uint8 constant STATE_DEPLOY_PROPOSAL0           = 2;
    uint8 constant STATE_DEPLOY_PROPOSAL1           = 3;
    uint8 constant STATE_DEPLOY_PROPOSAL2           = 4;
    uint8 constant STATE_DEPLOY_PROPOSAL3           = 5;
    uint8 constant STATE_DEPLOY_PROPOSAL4           = 6;
    uint8 constant STATE_DEPLOY_PROPOSAL5           = 7;
    uint8 constant STATE_DEPLOY_PROPOSAL6           = 8;
    uint8 constant STATE_DEPLOY_PROPOSAL7           = 9;
    uint8 constant STATE_DEPLOY_PROPOSAL8           = 10;
    uint8 constant STATE_DEPLOY_PROPOSAL9           = 11;
    uint8 constant STATE_DEPLOY_PROPOSAL10           = 12;
    uint8 constant STATE_DEPLOY_PROPOSAL11           = 13;
    uint8 constant STATE_DEPLOY_PROPOSAL12           = 14;
    uint8 constant STATE_DEPLOY_PROPOSAL13           = 15;
    uint8 constant STATE_DEPLOY_PROPOSAL14           = 16;
    uint8 constant STATE_DEPLOY_PROPOSAL15          = 17;
    uint8 constant STATE_DEPLOY_PROPOSAL16           = 18;

    uint8 constant STATE_DEPLOY_CONTEST1             =27;
    uint8 constant STATE_DEPLOY_CONTEST2             =28;
    uint8 constant STATE_DEPLOY_CONTEST3             =29;
    uint8 constant STATE_DEPLOY_CONTEST4             =30;
    uint8 constant STATE_DEPLOY_CONTEST5             =31;
    uint8 constant STATE_DEPLOY_CONTEST6             =32;
    uint8 constant STATE_DEPLOY_CONTEST7             =33;
    uint8 constant STATE_DEPLOY_CONTEST8             =34;
    uint8 constant STATE_DEPLOY_CONTEST9             =35;
    uint8 constant STATE_DEPLOY_CONTEST10             =36;
 
    uint32 constant ERROR_ZERO_VOTE_PRICE = 1001;

    uint64 constant DEPLOY_GAS_FEE = 5 ton;

    struct DeployProposal
    {
      uint256 id;
      uint128 totalVotes;
      uint32 startime;
      uint32 endtime;
      bytes desc;
      bool superMajority;
      uint256 votePrice;
      bool finalMsgEnabled;
      TvmCell finalMsg;
      uint256 finalMsgValue;
      uint256 finalMsgRequestValue;
      bool whiteListEnabled;
      uint256[] whitePubkeys;
    }

    struct DeployContest{
      bytes title;
      bytes link;
      uint256 hash;
      address juryAddr;
      uint256[] juryKeys;
      uint64 startsIn; 
      uint64 lastsFor; 
      uint64 votingWindow;
      uint256 sendApprovalGrams;
    }

    DeployProposal m_deployProposal;
    DeployContest m_deployContest;

    address m_msigDebot;
    address m_msig;
    address m_SuperRootAdr;

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
    
    function setMsigDebot(address md)public onlyOwnerAccept {
      m_msigDebot = md;
    }
    
    function setSuperRootAddress(address adr)public onlyOwnerAccept {
      m_SuperRootAdr = adr;
      m_target.set(m_SuperRootAdr);
      m_options |= DEBOT_TARGET_ADDR;
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
//====================================================
//=====================Deploy proposal
//====================================================
          contexts.push(Context(STATE_ZERO,
            "",
          [ ActionGoto("Deploy proposal" , STATE_DEPLOY_PROPOSAL0),
            ActionGoto("Quit" , STATE_EXIT) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL0,
            "Deploy Proposal:\nEnter your msig address:",
          [ ActionInstantRun  ("", "enterUserWallet", STATE_DEPLOY_PROPOSAL1) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL1,
            "Deploy Proposal:\nEnter proposal id:",
          [ ActionInstantRun  ("", "enterProposalId", STATE_DEPLOY_PROPOSAL3) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL3,
            "Deploy Proposal:\nEnter proposal total votes:",
          [ ActionInstantRun  ("", "enterProposalTotalVotes", STATE_DEPLOY_PROPOSAL4) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL4,
            "Deploy Proposal:\nEnter proposal start time in Unix timestamp format:",
          [ ActionInstantRun  ("", "enterProposalStartTime", STATE_DEPLOY_PROPOSAL5) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL5,
            "Deploy Proposal:\nEnter proposal endtime time in Unix timestamp format:",
          [ ActionInstantRun  ("", "enterProposalEndTime", STATE_DEPLOY_PROPOSAL6) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL6,
            "Deploy Proposal:\nEnter proposal description:",
          [ ActionInstantRun  ("", "enterProposalDescription", STATE_DEPLOY_PROPOSAL7) ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL7,
            "Deploy Proposal:\nIs proposal super majority:",
          [ ActionRun("Yes", "setProposalSuperMajorityTrue", STATE_DEPLOY_PROPOSAL8),
            ActionRun("No", "setProposalSuperMajorityFalse", STATE_DEPLOY_PROPOSAL8)] )); 

        contexts.push(Context(STATE_DEPLOY_PROPOSAL8,
            "Deploy Proposal:\nEnter proposal vote price (ton):",
          [ ActionInstantRun  ("", "enterProposalVotePrice", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_DEPLOY_PROPOSAL9), "instant") ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL9,
            "Deploy Proposal:\nDeploy contest on success?",
          [ ActionRun("Yes", "setProposalYesFinalMsg", STATE_DEPLOY_CONTEST1),//STATE_DEPLOY_PROPOSAL10),
            ActionRun("No", "setProposalNoFinalMsg", STATE_DEPLOY_PROPOSAL13)] )); 

  /*      contexts.push(Context(STATE_DEPLOY_PROPOSAL10,
            "Deploy Proposal:\nEnter proposal final message body in base64 format:",
          [ ActionInstantRun  ("", "enterProposalFinalMsg", STATE_DEPLOY_PROPOSAL11) ] ));
*/
        contexts.push(Context(STATE_DEPLOY_PROPOSAL11,
            "Deploy Proposal:\nEnter proposal final message value (ton):",
          [ ActionInstantRun  ("", "enterProposalFinalMsgValue", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_DEPLOY_PROPOSAL12), "instant") ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL12,
            "Deploy Proposal:\nEnter proposal final message request value (ton):",
          [ ActionInstantRun  ("", "enterProposalFinalMsgRequestValue", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_DEPLOY_PROPOSAL13), "instant") ] ));

        contexts.push(Context(STATE_DEPLOY_PROPOSAL13,
            "Deploy Proposal:\nIs white list enabled?",
          [ ActionRun("Yes", "setWhiteListTrue", STATE_DEPLOY_PROPOSAL14),
            ActionRun("No", "setWhiteListFalse", STATE_DEPLOY_PROPOSAL16)] )); 

        contexts.push(Context(STATE_DEPLOY_PROPOSAL14,
            "Deploy Proposal:\nEnter white list public key (in hex format starting with 0x):",
          [ ActionInstantRun  ("", "enterProposalWhiteListPubkey", STATE_DEPLOY_PROPOSAL15) ] )); 

        contexts.push(Context(STATE_DEPLOY_PROPOSAL15,
            "Deploy Proposal:\nEnter one more white list pubkey?",
          [ ActionGoto("Yes", STATE_DEPLOY_PROPOSAL14),
            ActionGoto("No",  STATE_DEPLOY_PROPOSAL16)] )); 

        contexts.push(Context(STATE_DEPLOY_PROPOSAL16,
            "Deploy Proposal?",
          [ 
            ActionInvokeDebot("Yes - let's deploy!", "invokeCreateProposal", STATE_EXIT),
            ActionGoto("No",  STATE_EXIT)] )); 

//====================================================
//=====================Deploy contest
//====================================================

        contexts.push(Context(STATE_DEPLOY_CONTEST1,
            "Deploy Contest:\nEnter contest title:",
          [ ActionInstantRun  ("", "enterContestTitle", STATE_DEPLOY_CONTEST2) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST2,
            "Deploy Contest:\nEnter contest link:",
          [ ActionInstantRun  ("", "enterContestLink", STATE_DEPLOY_CONTEST3) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST3,
            "Deploy Contest:\nEnter contest hash:",
          [ ActionInstantRun  ("", "enterContestHash", STATE_DEPLOY_CONTEST4) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST4,
            "Deploy Contest:\nEnter contest jury address:",
          [ ActionInstantRun  ("", "enterContestJuryAdr", STATE_DEPLOY_CONTEST5) ] ));

                contexts.push(Context(STATE_DEPLOY_CONTEST5,
            "Deploy Contest:\nEnter jury public key (in hex format starting with 0x):",
          [ ActionInstantRun  ("", "enterContestJuryPubkey", STATE_DEPLOY_CONTEST6) ] )); 

        contexts.push(Context(STATE_DEPLOY_CONTEST6,
            "Deploy Contest:\nEnter one more jury pubkey?",
          [ ActionGoto("Yes", STATE_DEPLOY_CONTEST5),
            ActionGoto("No",  STATE_DEPLOY_CONTEST7)] )); 

        contexts.push(Context(STATE_DEPLOY_CONTEST7,
            "Deploy Contest:\nEnter contest starts in:",
          [ ActionInstantRun  ("", "enterContestStart", STATE_DEPLOY_CONTEST8) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST8,
            "Deploy Contest:\nEnter contest starts lasts for:",
          [ ActionInstantRun  ("", "enterContestEnd", STATE_DEPLOY_CONTEST9) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST9,
            "Deploy Contest:\nEnter contest voting window:",
          [ ActionInstantRun  ("", "enterContestVotingWindow", STATE_DEPLOY_CONTEST10) ] ));

        contexts.push(Context(STATE_DEPLOY_CONTEST10,
            "Deploy Contest:\nEnter contest approval tons to send (ton):",
          [ ActionInstantRun  ("", "enterContestApprovalTon", STATE_CURRENT),
            ActionInstantRun  ("", "calcProposalFinalMsg", STATE_DEPLOY_PROPOSAL11)
           ] ));
//====================================================
//=====================End
//====================================================
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Create Proposal DeBot";
        semver = (0 << 8) | 1;
    }

    function quit() public override accept {}

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        if (error == ERROR_ZERO_VOTE_PRICE) {
            return "Vote price should not be zero";
        }
        return "Unknown exception! Code: "+string(error);
    }

    /*
     *   Handlers
     */
    function enterUserWallet(address msig) public accept {        
        m_msig = msig;
    }

    function enterProposalId(uint256 id) public accept {        
        m_deployProposal.id = id;
    }

    function enterProposalTotalVotes(uint128 totalVotes) public accept {        
        m_deployProposal.totalVotes = totalVotes;
    }

    function enterProposalStartTime(uint32 startime) public accept {        
        m_deployProposal.startime = startime;
    }

    function enterProposalEndTime(uint32 endtime) public accept {        
        m_deployProposal.endtime = endtime;
    }

    function enterProposalDescription(string desc) public accept {        
        m_deployProposal.desc = desc;
    }

    function setProposalSuperMajorityTrue() public accept {        
        m_deployProposal.superMajority = true;
    }
    
    function setProposalSuperMajorityFalse() public accept {        
        m_deployProposal.superMajority = false;
    }

    function enterProposalVotePrice(string votePrice) public view accept returns (Action[] actions) { 
        optional(string) none;
        actions = [ callEngine("convertTokens", votePrice, "setProposalVotePrice", none) ];
    }
    function setProposalVotePrice(uint64 arg1) public accept {
        require(arg1 != 0, ERROR_ZERO_VOTE_PRICE);
        m_deployProposal.votePrice = arg1;
    }

    function setProposalYesFinalMsg() public accept {        
        m_deployProposal.finalMsgEnabled = true;
    }
    
    function setProposalNoFinalMsg() public accept {        
        m_deployProposal.finalMsgEnabled = false;  
        m_deployProposal.finalMsgValue = 0;   
        m_deployProposal.finalMsgRequestValue = 0;  
        TvmCell empty;
        m_deployProposal.finalMsg = empty;
    }

    function enterProposalFinalMsg(TvmCell finalMsg) public accept {        
        m_deployProposal.finalMsg = finalMsg;
    }

    function enterProposalFinalMsgValue(string finalMsgValue) public view accept returns (Action[] actions) {        
        optional(string) none;
        actions = [ callEngine("convertTokens", finalMsgValue, "setProposalFinalMsgValue", none) ];
    }
    function setProposalFinalMsgValue(uint64 arg1) public accept {
        m_deployProposal.finalMsgValue = arg1;
    }

    function enterProposalFinalMsgRequestValue(string finalMsgRequestValue) public view accept returns (Action[] actions) {        
        optional(string) none;
        actions = [ callEngine("convertTokens", finalMsgRequestValue, "setProposalFinalMsgRequestValue", none) ];
    }
    function setProposalFinalMsgRequestValue(uint64 arg1) public accept {        
        m_deployProposal.finalMsgRequestValue = arg1;
    }

    function setWhiteListTrue() public accept {        
        m_deployProposal.whiteListEnabled = true;
        uint256[] nar;
        m_deployProposal.whitePubkeys = nar;
    }
    
    function setWhiteListFalse() public accept {        
        m_deployProposal.whiteListEnabled = false; 
        uint256[] nar; 
        m_deployProposal.whitePubkeys = nar;       
    }

    function enterProposalWhiteListPubkey(uint256 pubkey) public accept {
        m_deployProposal.whitePubkeys.push(pubkey);
    }

    function invokeCreateProposal() public accept returns (address debot, Action action) {
        debot = m_msigDebot;
        TvmCell payload = tvm.encodeBody(ISuperRoot.createProposal,m_deployProposal.id,m_deployProposal.totalVotes,
        m_deployProposal.startime,m_deployProposal.endtime,m_deployProposal.desc,m_deployProposal.superMajority,m_deployProposal.votePrice,
        m_deployProposal.finalMsgEnabled,m_deployProposal.finalMsg,m_deployProposal.finalMsgValue,m_deployProposal.finalMsgRequestValue,
        m_deployProposal.whiteListEnabled,m_deployProposal.whitePubkeys);
        uint64 amount =  uint64(m_deployProposal.finalMsgValue) + DEPLOY_GAS_FEE;
        action = invokeMsigHelperDebot(amount, payload);
    }
     
    function invokeMsigHelperDebot(uint64 amount, TvmCell payload) private returns (Action action) {
        TvmBuilder args;
        args.store(m_msig, m_SuperRootAdr, amount, uint8(1), uint8(3), payload);
        action = ActionSendMsg("", "sendSendTransactionEx", "instant,sign=by_user", STATE_EXIT);
        action.misc = args.toCell();
    }
/*Deploy contest */

    function enterContestTitle(bytes title) public accept {
        m_deployContest.title = title;
    } 
    function enterContestLink(bytes link) public accept {
        m_deployContest.link = link;
    }
    function enterContestHash(uint256 hash) public accept {
        m_deployContest.hash = hash;
    }
    function enterContestJuryAdr(address jadr) public accept {
        m_deployContest.juryAddr = jadr;
        uint256[] empty;
        m_deployContest.juryKeys = empty;
    } 
    function enterContestJuryPubkey(uint256 pkey) public accept {
        m_deployContest.juryKeys.push(pkey);
    } 
    function enterContestStart(uint64 startsIn) public accept {
        m_deployContest.startsIn = startsIn;
    } 
    function enterContestEnd(uint64 lastsFor) public accept {
        m_deployContest.lastsFor = lastsFor;
    }
    function enterContestVotingWindow(uint64 votingWindow) public accept {
        m_deployContest.votingWindow = votingWindow;
    }
    function enterContestApprovalTon(string sendApprovalGrams)public view accept returns (Action[] actions) {
       optional(string) none;
        actions = [ callEngine("convertTokens", sendApprovalGrams, "setContestApprovalTon", none) ];
    }
    function setContestApprovalTon(uint64 arg1) public accept {
         m_deployContest.sendApprovalGrams = arg1;
    }
    function calcProposalFinalMsg() public accept {
         TvmCell payload = tvm.encodeBody(AContest,m_deployContest.title,m_deployContest.link,m_deployContest.hash,m_deployContest.juryAddr,
         m_deployContest.juryKeys,m_deployContest.startsIn,m_deployContest.lastsFor,m_deployContest.votingWindow,m_deployContest.sendApprovalGrams);
         enterProposalFinalMsg(payload);
    }
    
}
