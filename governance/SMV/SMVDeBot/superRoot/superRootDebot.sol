pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

interface ISuperRoot {
    function createMultiBallot(uint256 pubkey, uint256 tonsToBallot) external returns(address value0);
    function createProposal(uint256 id, uint128 totalVotes,
    uint32 startime,uint32 endtime,bytes desc,bool superMajority,uint256 votePrice,bool finalMsgEnabled, TvmCell finalMsg, uint256 finalMsgValue,
    uint256 finalMsgRequestValue, bool whiteListEnabled, uint256[] whitePubkeys) external returns(bool value0);
}

contract SuperRootDebot is Debot, DError {

    /*
     * Context ids
     */
    uint8 constant STATE_PRE_MAIN                   = 1;
    uint8 constant STATE_DEPLOY_PROPOSAL0           = 2;
    uint8 constant STATE_DEPLOY_PROPOSAL1           = 3;
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

    uint8 constant STATE_DEPLOY_MULTIBALLOT0         = 19;
    uint8 constant STATE_DEPLOY_MULTIBALLOT1         = 20;
    uint8 constant STATE_DEPLOY_MULTIBALLOT3         = 22;
    uint8 constant STATE_DEPLOY_MULTIBALLOT4         = 23;

    uint8 constant STATE_PROPOSAL_IDS_LIST          =24;
    uint8 constant STATE_PROPOSAL_ADDRESS_BY_ID     =25;
    uint8 constant STATE_MULTIBALLOT_ADDRESS        =26;
     uint8 constant STATE_INFO_MENU                =27;

    uint32 constant ERROR_ZERO_VOTE_PRICE = 1001;

    uint64 constant DEPLOY_GAS_FEE = 0.5 ton;

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

    struct DeployMultiBallot
    {
      uint256 pubkey;
      uint256 tonstoballot;
    }

    DeployProposal m_deployProposal;
    DeployMultiBallot m_deployMultiBallot;

    address m_multiballotDebot;
    address m_proposalDebot;
    address m_msigDebot;
    address m_msig;
    address m_SuperRootAdr;
    address m_statDebot;

    uint256[] m_proposalIds;
    uint256 m_curProposalId;
    address m_curProposalAddress;
    address m_curMultiBallotAddress;
    uint256 m_curMultiBallotKey;
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
    
    function setProposalDebot(address adr)public onlyOwnerAccept {
      m_proposalDebot = adr;
    }

    function setMultiballotDebot(address adr)public onlyOwnerAccept {
      m_multiballotDebot = adr;
    }
    function setMsigDebot(address md)public onlyOwnerAccept {
      m_msigDebot = md;
    }
    function setStatDebot(address adr)public onlyOwnerAccept {
      m_statDebot = adr;
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
         contexts.push(Context(STATE_ZERO,
		    "Hello, I'm SMV Debot.\n", [     
            ActionInvokeDebot("Vote", "invokeMultiBallotDebot", STATE_ZERO),        
            ActionGoto("Deploy proposal", STATE_DEPLOY_PROPOSAL0),
            ActionGoto("Deploy MultiBallot" , STATE_DEPLOY_MULTIBALLOT0),
            ActionInvokeDebot("Show statistic", "invokeStatDebot", STATE_ZERO),
            ActionGoto("Additional information" , STATE_INFO_MENU),
            ActionGoto("Quit", STATE_EXIT) ] ));
//====================================================
//=====================Info menu
//====================================================
        contexts.push(Context(STATE_INFO_MENU,
		    "", [
            ActionGoto("Get proposal ids" , STATE_PROPOSAL_IDS_LIST),
            ActionGoto("Get proposal address by id" , STATE_PROPOSAL_ADDRESS_BY_ID),
            ActionGoto("Get multiballot address" , STATE_MULTIBALLOT_ADDRESS),
            ActionInvokeDebot("Show proposal info", "invokeProposalDebot", STATE_ZERO),
            ActionGoto("Return to main", STATE_ZERO) ] ));
//====================================================
//=====================Get proposal ids
//====================================================
        optional(string) empty;
        contexts.push(Context(STATE_PROPOSAL_IDS_LIST,
            "", [
            ActionGetMethod("querying proposal ids...", "getProposalIds", empty, 
            "setProposalIds", true, STATE_CURRENT),
            ActionInstantRun("List of proposal ids:", "fetchProposalIds", STATE_CURRENT),
            ActionGoto("Return to main", STATE_ZERO) ] ));
//====================================================
//=====================Get proposal address by id
//====================================================
        optional(string) args;
        args.set("getProposalId");
        contexts.push(Context(STATE_PROPOSAL_ADDRESS_BY_ID,
            "", [
            ActionInstantRun  ("Enter proposal id", "enterCurProposalId", STATE_CURRENT) , 
            ActionGetMethod("querying proposal address by id...", "getProposalAddress", args, 
            "setProposalAddress", true, STATE_CURRENT),
            ActionInstantRun("", "fetchProposalAddressById", STATE_CURRENT),
            ActionGoto("Return to main", STATE_ZERO) ] ));
//====================================================
//=====================Get multiballot address 
//====================================================
        args.set("getMultiBallotAddressParams");
        contexts.push(Context(STATE_MULTIBALLOT_ADDRESS,
            "", [
            ActionInstantRun  ("Enter MultiBallot public key", "enterMultiBallotPubKey", STATE_CURRENT),  
            //ActionInstantRun  ("Enter MultiBallot depool address", "enterMultiBallotDePoolAddress", STATE_CURRENT),  
            ActionGetMethod("", "getMultiBallotAddress", args, 
            "setMultiBallotAddress", true, STATE_CURRENT),
            ActionInstantRun("", "fetchMultiBallotAddress", STATE_CURRENT),
            ActionGoto("Return to main", STATE_ZERO) ] ));
//====================================================
//=====================Deploy multiballot
//====================================================
         contexts.push(Context(STATE_DEPLOY_MULTIBALLOT0,
            "Deploy MultiBallot:\nEnter your MultiSig wallet address to pay for MultiBallot deployment:",
          [ ActionInstantRun  ("", "enterUserWallet", STATE_DEPLOY_MULTIBALLOT1) ] ));
        contexts.push(Context(STATE_DEPLOY_MULTIBALLOT1,
            "Deploy MultiBallot:\n You need a keypair or seed phrase to subscribe your votes. Please remember it. Enter public key for that pair (in hex format starting with 0x):",
          [ ActionInstantRun  ("", "enterBallotPublicKey", STATE_DEPLOY_MULTIBALLOT3) ] ));
        contexts.push(Context(STATE_DEPLOY_MULTIBALLOT3,
            "Deploy MultiBallot:\nHow many tons would you like to send to ballot address for maintenance fee (ton):",
          [ ActionInstantRun  ("", "enterBallotTonsToBallot", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_DEPLOY_MULTIBALLOT4), "instant") ] ));
        contexts.push(Context(STATE_DEPLOY_MULTIBALLOT4,
            "Deploy MultiBallot?",
          [ 
            ActionInvokeDebot("Yes - let's deploy!", "invokeCreateMultiballot", STATE_ZERO),
            ActionGoto("No",  STATE_ZERO)] )); 
//====================================================
//=====================Deploy proposal
//====================================================
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
          [ ActionRun("Yes", "setProposalYesFinalMsg", STATE_DEPLOY_PROPOSAL10),
            ActionRun("No", "setProposalNoFinalMsg", STATE_DEPLOY_PROPOSAL13)] )); 

        contexts.push(Context(STATE_DEPLOY_PROPOSAL10,
            "Deploy Proposal:\nEnter proposal final message body in base64 format:",
          [ ActionInstantRun  ("", "enterProposalFinalMsg", STATE_DEPLOY_PROPOSAL11) ] ));

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
            ActionInvokeDebot("Yes - let's deploy!", "invokeCreateProposal", STATE_ZERO),
            ActionGoto("No",  STATE_ZERO)] )); 
//====================================================
//=====================End
//====================================================
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "SMV DeBot";
        semver = (1 << 8) | 0;
    }

    function quit() public override accept {}

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        if (error == ERROR_ZERO_VOTE_PRICE) {
            return "Vote price should not be zero";
        }
        return "unknown exception";
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
        m_deployProposal.whitePubkeys = new uint256[](0);
    }
    
    function setWhiteListFalse() public accept {        
        m_deployProposal.whiteListEnabled = false; 
        m_deployProposal.whitePubkeys = new uint256[](0);
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
        uint64 amount =  uint64(m_deployProposal.finalMsgValue) + DEPLOY_GAS_FEE*2;
        action = invokeMsigDebot(amount, payload);
    }
     
/*Deploy multiballot*/

    function enterBallotPublicKey(uint256 pubkey) public accept {
        m_deployMultiBallot.pubkey = pubkey;
    }

    function enterBallotTonsToBallot(string tonstoballot) public view accept returns (Action[] actions) {
       optional(string) none;
        actions = [ callEngine("convertTokens", tonstoballot, "setBallotTonsToBallot", none) ];
        
    }
    function setBallotTonsToBallot(uint64 arg1) public accept {
        m_deployMultiBallot.tonstoballot = arg1;
    }    

    function invokeCreateMultiballot() public accept returns (address debot, Action action) {
        debot = m_msigDebot;
        TvmCell payload = tvm.encodeBody(ISuperRoot.createMultiBallot, m_deployMultiBallot.pubkey, m_deployMultiBallot.tonstoballot);
        uint64 amount =  uint64(m_deployMultiBallot.tonstoballot) + DEPLOY_GAS_FEE;
        action = invokeMsigDebot(amount, payload);
    }

    function invokeMsigDebot(uint64 amount, TvmCell payload) private returns (Action action) {
        TvmBuilder args;
        args.store(m_msig, m_SuperRootAdr, amount, uint8(1), uint8(0), payload);
        action = ActionSendMsg("", "sendSubmitMsgEx", "instant,sign=by_user", STATE_EXIT);
        action.misc = args.toCell();
    }

/*proposal ids list*/

     function setProposalIds(uint256[] value0) public accept {
        m_proposalIds = value0;
    }

    function fetchProposalIds() public accept returns (Action[] actions) {
        for(uint256 i = 0; i < m_proposalIds.length; i++) {
            Action act = ActionPrint("", "#{}", STATE_CURRENT);
            act.attrs = "instant,fargs=parseProposalIds";
            TvmBuilder ctx;
            ctx.store(m_proposalIds[i]);
            act.misc = ctx.toCell();
            actions.push(act);
        }
    }

    function parseProposalIds(TvmCell misc) public accept returns (uint256 number0) {
        (number0) = misc.toSlice().decode(uint256);
    }

/*Get proposal address by id */

    function enterCurProposalId(uint256 prop_id) public accept {
        m_curProposalId = prop_id;
    }

    function setProposalAddress(address value0) public accept {
        m_curProposalAddress = value0;
    }

    function fetchProposalAddressById() public accept returns (Action[] actions) {
            Action act = ActionPrint("", "Proposal:\n id={};\n address={}", STATE_CURRENT);
            act.attrs = "instant,fargs=parseProposalAddressById";
            TvmBuilder ctx;
            ctx.store(m_curProposalId,m_curProposalAddress);
            act.misc = ctx.toCell();
            actions.push(act);
    }

    function parseProposalAddressById(TvmCell misc) public accept returns (uint256 number0,address param1 ) {
        (number0,param1) = misc.toSlice().decode(uint256,address);
    }

    function getProposalId() public accept returns (uint256 id) {
        return m_curProposalId;
    }

/*Get multiballot address*/

    function enterMultiBallotPubKey(uint256 pkey) public accept {
        m_curMultiBallotKey = pkey;
    } 

    function setMultiBallotAddress(address value0) public accept {
        m_curMultiBallotAddress = value0;
    } 
    function getMultiBallotAddressParams() public accept returns (uint256 pubkey) {
        pubkey = m_curMultiBallotKey;
    }

    function fetchMultiBallotAddress() public accept returns (Action[] actions) {
        Action act = ActionPrint("", "MultiBallot:\n pubkey ={}\n address={}", STATE_CURRENT);
        act.attrs = "instant,fargs=parseMultiBallotAddress";
        TvmBuilder ctx;
        ctx.store(m_curMultiBallotKey,m_curMultiBallotAddress);
        act.misc = ctx.toCell();
        actions.push(act);
    }

    function parseMultiBallotAddress(TvmCell misc) public accept returns (uint256 param0,address param1 ) {
        (param0,param1) = misc.toSlice().decode(uint256,address);
    }
    
/*incoke debots*/
    function invokeMultiBallotDebot() public view returns (address debot, Action action) {
        tvm.accept();
        debot = m_multiballotDebot;
        action = Action("", "", ACTION_MOVE_TO, "instant", 0, empty); 
    }

    function invokeProposalDebot() public view returns (address debot, Action action) {
        tvm.accept();
        debot = m_proposalDebot;
        action = Action("", "", ACTION_MOVE_TO, "instant", 0, empty); 
    }

    function invokeStatDebot() public view returns (address debot, Action action) {
        tvm.accept();
        debot = m_statDebot;
        action = Action("", "", ACTION_MOVE_TO, "instant", 0, empty); 
    }

   
}
