pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

interface IDepool {
    function transferStake(address dest, uint64 amount) external;
}

interface IMultiballot {
    function sendVote(address proposal,bool yesOrNo) external returns(uint256 has_deposit,uint256 already_sent_deposit,uint256 new_sent_deposit);// functionID(0xd);
    function receiveNativeTransfer(uint256 amount) external;
    function requestDeposit(address user_wallet) external;
}

contract MultiBallotDebot is Debot, DError {
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
      uint256[] wlist;
    }
    /*
     * Context ids
     */
    uint8 constant STATE_MAIN                  = 1;
    uint8 constant STATE_VOTE1                 = 2;
    uint8 constant STATE_VOTE2                 = 3;
    uint8 constant STATE_VOTE3                 = 4;
    uint8 constant STATE_STAKE_MSIG1           = 5;
    uint8 constant STATE_STAKE_MSIG2           = 6;
    uint8 constant STATE_STAKE_MSIG3           = 7;
    uint8 constant STATE_STAKE_DEPOOL0         = 8;
    uint8 constant STATE_STAKE_DEPOOL1         = 9;
    uint8 constant STATE_STAKE_DEPOOL2         = 10;
    uint8 constant STATE_STAKE_DEPOOL3         = 11;
    uint8 constant STATE_WITHDRAW1             = 12;
    uint8 constant STATE_WITHDRAW2             = 13;
    uint8 constant STATE_GET_DEPOSIT           = 14;

    uint8 constant STATE_PROPOSAL_VOTE1        = 15;
    
    uint32 constant ERROR_ACCOUNT_NOT_EXIST    = 1000;
    uint32 constant ERROR_NO_DEPOSIT           = 1001;

    uint64 constant TRANSFER_GAS_FEE = 0.25 ton;

    address m_msigDebot;
    address m_msig;
    uint64 m_msigAmount;
    address m_MultiBallotDePool;
    uint256 m_MultiBallotPubkey;

    address m_curProposalAddress;
    bool m_curVote;

    uint256 m_nativeDeposit;
    uint256 m_stakeDeposit;

    string m_mbAbi;
    address m_mbAddress;
    string m_srAbi;
    address m_srAddress;
    string m_prAbi;
    address m_prAddress;

    uint256[] m_proposalIds;
    uint256 m_proposalIdsCount;

    address[] m_proposalAddresses;
    ProposalInfo[] m_proposalInfos;
    address[] m_notfinishedAddresses;
    ProposalInfo[] m_notfinishedProposals;
    
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
    
    function setABI(string dabi) public onlyOwnerAccept {
        m_debotAbi.set(dabi);
        m_options |= DEBOT_ABI;
    }

    function setTargetABI(string tabi) public onlyOwnerAccept {
        m_targetAbi.set(tabi);
        m_options |= DEBOT_TARGET_ABI;
    }

    function setMbAbi(string dabi) public onlyOwnerAccept {
        m_mbAbi = dabi;
    }
    
    function setSrAbi(string dabi) public onlyOwnerAccept {
        m_srAbi = dabi;
    }

    function setSrAddr(address addr) public onlyOwnerAccept {
        m_srAddress = addr;
    }

    function setPrAbi(string dabi) public onlyOwnerAccept {
        m_prAbi = dabi;
    }

     /*
     *   Derived Debot Functions
     */

    function fetch() public override accept returns (Context[] contexts) {
        optional(string) none;
 	    optional(string) args;
        args.set("getMultiBallotAddressParams");
        optional(string) args1;
        args1.set("getMultiBallotAddress");
        

        contexts.push(Context(STATE_ZERO,
		    "Hello, I'm MultiBallot Debot.\n", [             
             ActionInstantRun("Enter your multiballot public key", "enterMultiBallotPubkey", STATE_CURRENT) , 
             ActionInstantRun("", "selectSuperRoot", STATE_CURRENT) , 
             ActionGetMethod("", "getMultiBallotAddress", args, "setMyMBAddress", true, STATE_CURRENT),
             ActionInstantRun("", "fetchMultiBallotAddress", STATE_CURRENT),
             callEngine("getAccountState", "", "checkMultiBallotAddress", args1),
             ActionInstantRun("", "selectMultiBallot", STATE_CURRENT) ,
             setAttrs(ActionGoto("", STATE_MAIN), "instant")
             ] ));


        contexts.push(Context(STATE_MAIN,
		    "", [             
            ActionGoto("Vote" , STATE_PROPOSAL_VOTE1),
            ActionGoto("Vote by proposal address" , STATE_VOTE1),
            ActionGoto("Get total deposit" , STATE_GET_DEPOSIT),
            ActionGoto("Add deposit from msig" , STATE_STAKE_MSIG1),
            ActionGoto("Add deposit from depool" , STATE_STAKE_DEPOOL0),
            ActionGoto("Withdraw deposit" , STATE_WITHDRAW1),
            ActionGoto("Return to main", STATE_EXIT) ] ));

//====================================================
//=====================Get total deposit
//====================================================
        //optional(string) none;
        optional(string) fargs;
        fargs.set("parseDeposit");
        contexts.push(Context(STATE_GET_DEPOSIT,
		    "Hello, I'm SMV Debot.\n", [             
            ActionGetMethod("querying native deposit...", "getNativeDeposit", none, 
            "setNativeDeposit", true, STATE_CURRENT),
            ActionGetMethod("querying stake deposit...", "getStakeDeposit", none, 
            "setStakeDeposit", true, STATE_CURRENT),
            ActionPrintEx("", "Deposit:\n native={}.{} ton\n stake ={}.{} ton\n total ={}.{} ton", true, fargs, STATE_CURRENT),
            ActionGoto("Return", STATE_MAIN) ] ));
//====================================================
//=====================Vote
//====================================================
        contexts.push(Context(STATE_PROPOSAL_VOTE1,
            "",
          [  ActionGetMethod("", "getNativeDeposit", none, "setNativeDeposit", true, STATE_CURRENT),
             ActionGetMethod("", "getStakeDeposit", none, "setStakeDeposit", true, STATE_CURRENT),
             ActionInstantRun("", "checkMultiBallotDeposit", STATE_CURRENT),             
             ActionInstantRun("", "selectSuperRoot", STATE_CURRENT) , 
             ActionGetMethod("", "getProposalIds", none, "setProposalIds", true, STATE_CURRENT),
             ActionInstantRun("", "proposalIdsToAddresses", STATE_CURRENT),
             ActionInstantRun("", "selectProposalRoot", STATE_CURRENT) ,              
             ActionInstantRun("", "proposalAddressesToInfos", STATE_CURRENT),
             ActionInstantRun("", "filterProposalInfos", STATE_CURRENT),
             ActionInstantRun("", "selectMultiBallot", STATE_CURRENT) ,
             ActionGetMethod("", "getNativeDeposit", none, "setNativeDeposit", true, STATE_CURRENT),
             ActionGetMethod("", "getStakeDeposit", none, "setStakeDeposit", true, STATE_CURRENT),
             ActionInstantRun("Available proposal:", "fetchAvailableProposal", STATE_CURRENT), 
             ActionGoto("Return", STATE_MAIN)
              ] ));
//====================================================
//=====================Vote by address
//====================================================
        contexts.push(Context(STATE_VOTE1,
            "Enter proposal address:",
          [ ActionInstantRun  ("", "enterProposalAddress", STATE_VOTE2) ] ));
          
        contexts.push(Context(STATE_VOTE2,
            "What to say:",
          [ ActionRun("Say Yes!", "setVoteYes", STATE_VOTE3),
            ActionRun("Say No!", "setVoteNo", STATE_VOTE3)] )); 

        contexts.push(Context(STATE_VOTE3,
            "Send vote:",
          [ ActionInstantRun("", "selectMultiBallot", STATE_CURRENT) ,
            ActionSendMsg("Yes!", "sendVoteMsg", "sign=by_user", STATE_MAIN),
            ActionGoto("Cancel", STATE_MAIN)])); 
//====================================================
//=====================add stake from msig
//====================================================
        contexts.push(Context(STATE_STAKE_MSIG1,
            "From what MultiSig walet address do you want to transfer deposit:",
          [ ActionInstantRun  ("", "enterMsigAddress", STATE_STAKE_MSIG2) ] ));
          
        contexts.push(Context(STATE_STAKE_MSIG2,
            "Enter amount to transfer (ton):",
          [ ActionInstantRun  ("", "enterMsigAmount", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_STAKE_MSIG3), "instant")] )); 

        contexts.push(Context(STATE_STAKE_MSIG3,
            "Transfer deposit?",
          [
            ActionInvokeDebot("Yes!", "invokeSendMsig", STATE_MAIN),
            ActionGoto("Cancel", STATE_MAIN)])); 
//====================================================
//=====================add stake from depool
//====================================================
        fargs.set("parseDepool");
        contexts.push(Context(STATE_STAKE_DEPOOL0,
            "",
          [ActionGetMethod("", "getDepool", none, 
            "setMultiBallotDePool", true, STATE_CURRENT),
           ActionPrintEx("", "Depool address: {}", true, fargs, STATE_STAKE_DEPOOL1)
            ] ));

        contexts.push(Context(STATE_STAKE_DEPOOL1,
            "Enter your account address at depool:",
          [ ActionInstantRun  ("", "enterMsigAddress", STATE_STAKE_DEPOOL2) ] ));
          
        contexts.push(Context(STATE_STAKE_DEPOOL2,
            "Enter amount to transfer (ton):",
          [ ActionInstantRun  ("", "enterMsigAmount", STATE_CURRENT),
            setAttrs(ActionGoto("", STATE_STAKE_DEPOOL3), "instant")] )); 

        contexts.push(Context(STATE_STAKE_DEPOOL3,
            "Transfer stake?",
          [
            ActionInvokeDebot("Yes!", "invokeTransferStake", STATE_MAIN),
            ActionGoto("Cancel", STATE_MAIN)])); 
//====================================================
//=====================withdraw stake
//====================================================
        contexts.push(Context(STATE_WITHDRAW1,
            "Enter your msig address for withdraw all deposits:",
          [ ActionInstantRun  ("", "enterMsigAddress", STATE_WITHDRAW2) ] ));
          
        contexts.push(Context(STATE_WITHDRAW2,
            "withdraw all:",
          [
            ActionSendMsg("Yes!", "sendRequestDepositMsg", "sign=by_user", STATE_MAIN),
            ActionGoto("Cancel",  STATE_MAIN)])); 
//====================================================
//=====================End
//====================================================
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "MultiBallot DeBot";
        semver = (0 << 8) | 1;
    }

    function quit() public override accept {}

    function getErrorDescription(uint32 error) public view override returns (string desc) {
        if(error==100){
            return "Wrong seed phrase";
        } 
        if(error==101){
            return "Not enough balance";
        }
        if(error==104){
            return "Deposit already requested";
        }
        if(error==ERROR_ACCOUNT_NOT_EXIST) {
            return "MultiBallot doesn't active. Try to deploy it first or add some tons to the balance!";
        }if(error==ERROR_NO_DEPOSIT) {
            return "You have no deposit. Please make deposit form your walet or DePool!";
        }
        return "unknown exception:"+string(error);
    }

    /*
     *   Handlers
     */
    function selectMultiBallot() public accept {
        m_targetAbi.set(m_mbAbi);   
        m_options |= DEBOT_TARGET_ABI;
        m_target.set(m_mbAddress);
        m_options |= DEBOT_TARGET_ADDR;
    }

    function selectSuperRoot() public accept {        
        m_targetAbi.set(m_srAbi);   
        m_options |= DEBOT_TARGET_ABI;
        m_target.set(m_srAddress);
        m_options |= DEBOT_TARGET_ADDR;
    }

    function selectProposalRoot() public accept {
        m_targetAbi.set(m_prAbi);   
        m_options |= DEBOT_TARGET_ABI;
        m_target.set(m_prAddress);
        m_options |= DEBOT_TARGET_ADDR;
    }

    function enterMultiBallotAddress(address adr) public accept {        
        m_target.set(adr);
        m_options |= DEBOT_TARGET_ADDR;
    }

    function checkMultiBallotDeposit() public view accept {       
        require(m_nativeDeposit>0||m_nativeDeposit>0, ERROR_NO_DEPOSIT);
    }
    
/* get address by pub key*/

    function enterMultiBallotPubkey(uint256 pubkey) public accept {        
        m_MultiBallotPubkey = pubkey;
    }
    function getMultiBallotAddress() public view accept returns (address addr) {
        addr = m_mbAddress;
    }
    function setMyMBAddress(address value0) public accept {
        m_mbAddress = value0;
    } 
    function getMultiBallotAddressParams() public view accept returns (uint256 pubkey) {
        pubkey = m_MultiBallotPubkey;
    }

     function fetchMultiBallotAddress() public view accept returns (Action[] actions) {
            Action act = ActionPrint("", "MultiBallot:\n pubkey ={}\n address={}", STATE_CURRENT);
            act.attrs = "instant,fargs=parseMultiBallotAddress";
            TvmBuilder ctx;
            ctx.store(m_MultiBallotPubkey,m_mbAddress);
            act.misc = ctx.toCell();
            actions.push(act);
    }
    

    function parseMultiBallotAddress(TvmCell misc) public pure accept returns (uint256 param0,address param1 ) {
        (param0,param1) = misc.toSlice().decode(uint256,address);
    }

    function checkMultiBallotAddress(
        uint256 balance,
        int8 acc_type,
        uint64 last_trans_lt,
        TvmCell code,
        TvmCell data,
        TvmCell lib
    ) public pure accept {
        require(acc_type==1,ERROR_ACCOUNT_NOT_EXIST);
    } 


/* vote */

    function fetchAvailableProposal() public view accept returns (Action[] actions) {        
        for(uint256 i = 0; i < m_notfinishedProposals.length; i++) {
            Action act = ActionPrint("", "Proposal info:\n id: {}\n description: {}\n start time: {}\n end time: {}\n total votes: {}\n yes votes: {}\n no votes: {}\n vote price (ton): {}.{}\n\n Your total vote will be: {} votes\n Your tokens will be locked until {}", STATE_CURRENT);
            act.attrs = "instant,fargs=parsePPInfo";

            TvmBuilder ctx;
            ctx.store(m_notfinishedProposals[i].id,m_notfinishedProposals[i].start,m_notfinishedProposals[i].end,m_notfinishedProposals[i].totalVotes, m_notfinishedProposals[i].desc, m_notfinishedProposals[i].yesVotes, m_notfinishedProposals[i].noVotes,m_notfinishedProposals[i].votePrice);

            act.misc = ctx.toCell();
            actions.push(act);

            TvmBuilder yesBuilder;
            yesBuilder.store(m_notfinishedAddresses[i],uint8(1));
            TvmCell yesCell = yesBuilder.toCell();

            act = ActionRun("Say Yes", "setVoteProposal", STATE_VOTE3);
            act.misc = yesCell;
            actions.push(act);

            TvmBuilder noBuilder;
            noBuilder.store(m_notfinishedAddresses[i],uint8(0));
            TvmCell noCell = noBuilder.toCell();

            act = ActionRun("Say No", "setVoteProposal", STATE_VOTE3);
            act.misc = noCell;
            actions.push(act);
            
        }
    }
    
    function filterProposalInfos() public accept {        
        m_notfinishedAddresses = new address[](0);
        m_notfinishedProposals = new ProposalInfo[](0);
        for(uint256 i = 0; i < m_proposalInfos.length; i++) {
            if (!m_proposalInfos[i].finished){
                if (m_proposalInfos[i].whiteListEnabled){
                    bool bFind = false;
                    for (uint256 j = 0; j < m_proposalInfos[i].wlist.length; j++) {
                        if (m_MultiBallotPubkey == m_proposalInfos[i].wlist[j]){
                            bFind = true;
                            break;
                        }
                    }
                    if (bFind) {
                        m_notfinishedAddresses.push(m_proposalAddresses[i]);
                        m_notfinishedProposals.push(m_proposalInfos[i]);
                    }
                }else{
                    m_notfinishedAddresses.push(m_proposalAddresses[i]);
                    m_notfinishedProposals.push(m_proposalInfos[i]);
                }
            }
        }
    }

   function parsePPInfo(TvmCell misc) public view accept returns (uint256 number0,string str1, uint32 utime2,uint32 utime3,uint128 number4, uint128 number5,uint128 number6,uint64 number7,uint64 number8, uint128 number9, uint32 utime10) {
      uint256 votePrice;
      bytes bar;
      (number0, utime2, utime3, number4,bar,number5,number6,votePrice)= misc.toSlice().decode(uint256, uint32, uint32, uint128, bytes, uint128, uint128, uint256);
      str1 = string(bar);
      (number7, number8) = tokens(votePrice);
      number9 = uint128((m_nativeDeposit+m_stakeDeposit)/votePrice);
      utime10 = utime3;
    }


    function setProposalAddress(address value0) public accept {
        m_proposalAddresses.push(value0);
    }
   function setProposalIds(uint256[] value0) public accept {

        m_proposalIds = value0;
    }

    function getProposalId() public accept returns (uint256 id) {
        id = m_proposalIds[m_proposalIdsCount];
        m_proposalIdsCount++;
    }

    function proposalIdsToAddresses() public accept returns (Action[] actions) {
        optional(string) args;
        args.set("getProposalId");
        m_proposalAddresses = new address[](0);
        m_proposalInfos = new ProposalInfo[](0);
        m_proposalIdsCount = 0;
        for(uint256 i = 0; i < m_proposalIds.length; i++) {
            Action act =  ActionGetMethod("", "getProposalAddress", args, "setProposalAddress", true, STATE_CURRENT);
            actions.push(act);
        }
    }

    function setTargetForGetInfo() public accept returns (Action[] actions) {
        m_target.set(m_proposalAddresses[m_proposalIdsCount]);
        m_proposalIdsCount++;
    }

    function setMyPropInfo(uint256 id,uint32 start,uint32 end,bytes desc,bool finished, bool approved,bool resultsSent,bool earlyFinished,
        bool whiteListEnabled, uint128 totalVotes, uint128 currentVotes, uint128 yesVotes, uint128 noVotes,uint256 votePrice) public accept {
            ProposalInfo proposalInfo;
            proposalInfo.id = id;
            proposalInfo.start = start;
            proposalInfo.end = end;
            proposalInfo.desc = desc;
            proposalInfo.finished = finished;
            proposalInfo.approved = approved;
            proposalInfo.resultsSent = resultsSent;
            proposalInfo.earlyFinished = earlyFinished;
            proposalInfo.whiteListEnabled = whiteListEnabled;
            proposalInfo.totalVotes = totalVotes;
            proposalInfo.currentVotes = currentVotes;
            proposalInfo.yesVotes = yesVotes;
            proposalInfo.noVotes = noVotes;
            proposalInfo.votePrice = votePrice;
            m_proposalInfos.push(proposalInfo);
      }  

    function setProposalWhitelist(uint256[] value0) public accept {
          m_proposalInfos[m_proposalInfos.length-1].wlist = value0;
     }

    function proposalAddressesToInfos() public accept returns (Action[] actions) {
        m_proposalIdsCount = 0;
        optional(string) empty;
        for(uint256 i = 0; i < m_proposalAddresses.length; i++) {
            Action act = ActionInstantRun("", "setTargetForGetInfo", STATE_CURRENT);
            actions.push(act);            
            Action act1 = ActionGetMethod("", "getProposal", empty,"setMyPropInfo", true, STATE_CURRENT);
            actions.push(act1);
            Action act2 = ActionGetMethod("", "getWhiteList", empty, "setProposalWhitelist", true, STATE_CURRENT);
            actions.push(act2);
           
        }
    }

/* vote by address */

    function setMultiBallotDePool(address value0) public accept {        
        m_MultiBallotDePool = value0;
    }
               
    function enterProposalAddress(address adr) public accept {        
        m_curProposalAddress = adr;
    }
    function setVoteProposal(TvmCell misc) public accept {
        uint8 vote;
        (m_curProposalAddress,vote) = misc.toSlice().decode(address,uint8);
        m_curVote = vote==1? true: false;
    }

    function setVoteYes() public accept {        
        m_curVote = true;
    }

    function setVoteNo() public accept {        
        m_curVote = false;
    }

    function sendVoteMsg() public accept view returns (address dest, TvmCell body) {
        dest = m_target.get();
        body = tvm.encodeBody(IMultiballot.sendVote,m_curProposalAddress,m_curVote);
    }

/* deposit managnment */

    function enterMsigAddress(address adr) public accept {        
        m_msig = adr;
    }

    function enterMsigAmount(string amount) public view accept returns (Action[] actions) {
        optional(string) none;
        actions = [ callEngine("convertTokens", amount, "setMsigAmount", none) ];
    }

    function setMsigAmount(uint64 arg1) public accept {
        m_msigAmount = arg1;
    }

    function invokeSendMsig() public view accept returns (address debot, Action action) {
        debot = m_msigDebot;
        TvmCell payload = tvm.encodeBody(IMultiballot.receiveNativeTransfer, m_msigAmount);
        uint64 amount =  m_msigAmount + TRANSFER_GAS_FEE;
        action = invokeMsigDebot(amount, m_target.get(), payload);
    }

    function invokeMsigDebot(uint64 amount, address dst, TvmCell payload) private view returns (Action action) {
        TvmBuilder args;
        args.store(m_msig, dst, amount, uint8(1), uint8(0), payload);
        action = ActionSendMsg("", "sendSubmitMsgEx", "instant,sign=by_user", STATE_EXIT);
        action.misc = args.toCell();
    }

    function invokeTransferStake() public view accept returns (address debot, Action action) {
        debot = m_msigDebot;
        TvmCell payload = tvm.encodeBody(IDepool.transferStake,
            m_target.get(), uint64(m_msigAmount));
        uint64 amount = TRANSFER_GAS_FEE;
        action = invokeMsigDebot(amount, m_MultiBallotDePool, payload);
    }    

    function sendRequestDepositMsg() public accept view returns (address dest, TvmCell body) {
        dest = m_target.get();
        body = tvm.encodeBody(IMultiballot.requestDeposit,m_msig);
    }

/* get total deposit */

    function setNativeDeposit(uint256 value0) public accept {
        m_nativeDeposit = value0;
    }
    function setStakeDeposit(uint256 value0) public accept {
        m_stakeDeposit = value0;
    }

    function parseDeposit() public view accept returns (uint64 number0, uint64 number1, uint64 number2, uint64 number3, uint64 number4, uint64 number5) {
        (number0,number1) = tokens(m_nativeDeposit);
        (number2,number3) = tokens(m_stakeDeposit);
        (number4,number5) = tokens(m_nativeDeposit+m_stakeDeposit);
    }

    function parseDepool() public view accept returns (address param0) {
        (param0) = m_MultiBallotDePool;
    }

    function tokens(uint256 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }
    
}
