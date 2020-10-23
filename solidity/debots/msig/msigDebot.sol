pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

interface IMultisig {
    function submitTransaction(
        address  dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload)
    external returns (uint64 transId);

    function confirmTransaction(uint64 transactionId) external;

    function constructor1(uint256[] owners, uint8 reqConfirms) external functionID(0x6C1E693C);
}

contract MultisigDebot is Debot, DError {

    // Debot context ids
    uint8 constant STATE_PRE_MAIN       = 1;
    uint8 constant STATE_MAIN           = 2;
    uint8 constant STATE_CONFIRM        = 3;
    uint8 constant STATE_DETAILS        = 4;
    uint8 constant STATE_BALANCE        = 5;
    uint8 constant STATE_CUSTODIANS     = 6;
    uint8 constant STATE_SUBMIT         = 7;
    uint8 constant STATE_SUBMIT_AMOUNT  = 8;
    uint8 constant STATE_SUBMIT_BOUNCE  = 9;
    uint8 constant STATE_SUBMIT_SEND    = 10;
    uint8 constant STATE_DEPLOY         = 11;
    uint8 constant STATE_DEPLOY_STEP2   = 12;
    uint8 constant STATE_DEPLOY_STEP3   = 13;
    uint8 constant STATE_DEPLOY_STEP4   = 14;
    uint8 constant STATE_DEPLOY_STEP5   = 15;
    uint8 constant STATE_DEPLOY_STEP6   = 16;

    // Helper structure to accumulate info about new transaction
    struct Txn {
        address  dest;
        uint128 amount;
        bool bounce;
        TvmCell payload;
    }

    // A copy of structure from multisig contract
    struct Transaction {
        // Transaction Id.
        uint64 id;
        // Transaction confirmations from custodians.
        uint32 confirmationsMask;
        // Number of required confirmations.
        uint8 signsRequired;
        // Number of confirmations already received.
        uint8 signsReceived;
        // Public key of custodian queued transaction.
        uint256 creator;
        // Index of custodian.
        uint8 index;
        // Destination address of token transfer.
        address  dest;
        // Amount of nanogtokens to transfer.
        uint128 value;
        // Flags for sending internal message (see SENDRAWMSG in TVM spec).
        uint16 sendFlags;
        // Payload used as body of outbound internal message.
        TvmCell payload;
        // Bounce flag for header of outbound internal message.
        bool bounce;
    }

    // A Copy of a structure from multisig contract
    struct CustodianInfo {
        uint8 index;
        uint256 pubkey;
    }

    // Helper structure for accumulating constructor parameters 
    // and deploy data for new wallet 
    struct DeployData {
        TvmCell stateInit;
        uint256 pubkey;
        uint8 reqConfirms;
        uint8 custodians;
        uint256[] custodianKeys;
        address addr;
    }

    /*
        Storage
    */

    // Used in `submit` action steps
    Txn m_txn;
    // Stores current txn id between several steps
    uint64 m_curTxnId;
    // Pending transactions received from target multisig
    Transaction[] m_pendingTxns;
    // Custodians received from target multisig
    CustodianInfo[] m_custodians;
    // Target wallet balance
    uint128 m_balance;
    // Used in `deploy new wallet` action steps
    DeployData m_deployData;
    
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
            "Hello, I'm a Multisig Debot 🙂. What would you like to do today?", [
            ActionRun("Use an existing wallet - If you already have a wallet, just enter its address",
                "enterTargetAddress", STATE_PRE_MAIN),
            ActionGoto("Deploy a new wallet - if you don't have a wallet yet, you can deploy a new one", STATE_DEPLOY),
            ActionPrint("Quit", "quit", STATE_EXIT) ] ));

        // Pre main state: call get-methods of target wallet.
        contexts.push(Context(STATE_PRE_MAIN, 
            "", [
            Action("querying pending transactions...", 
                "setPendingTxns", ACTION_RUN_METHOD, "instant,func=getTransactions", STATE_PRE_MAIN, empty),
            Action("querying custodians...",
                "setCustodians", ACTION_RUN_METHOD, "instant,func=getCustodians", STATE_MAIN, empty) ] ));

        // main state
        contexts.push(Context(STATE_MAIN,
            "Main menu:", [
            ActionInstantRun("", "fetchTransactions", STATE_CURRENT),
            ActionGoto ("Balance - view wallet balance", STATE_BALANCE),
            ActionGoto ("Custodians - view custodian public keys", STATE_CUSTODIANS),
            ActionGoto ("Submit - create new transaction", STATE_SUBMIT),
            ActionPrint("Quit", "Bye!", STATE_EXIT) ] ));
		
        contexts.push(Context(STATE_CONFIRM,
            "Are you sure?", [
            ActionSendMsg("Yes", "sendConfirmMsg", "sign=by_user", STATE_PRE_MAIN),
            ActionPrint  ("No", "Ok, never mind.", STATE_PRE_MAIN) ]));
        
        contexts.push(Context(STATE_DETAILS,
            "Transaction details:", [
            Action("", "created at: {}\nexpired after: {} min\nsigns received/required: {}/{}\ncreator public key : {}\nflags: {}\n",
                ACTION_PRINT, "instant,fargs=parseTxnDetails", STATE_DETAILS, empty),
            ActionGoto("Return to main", STATE_PRE_MAIN) ] ));
		
        optional(string) fargs;
        fargs.set("parseBalanceArgs");
        contexts.push(Context(STATE_BALANCE,
            "Wallet balance:", [
            ActionInstantRun("", "queryBalance", STATE_CURRENT),
            ActionPrintEx("", "{}.{}", true, fargs, STATE_CURRENT),
            ActionGoto("Return to main", STATE_PRE_MAIN) ] ));

        contexts.push(Context(STATE_CUSTODIANS,
            "List of custodians:", [
            ActionInstantRun("", "fetchCustodians", STATE_CURRENT),
            ActionGoto("Return to main", STATE_PRE_MAIN) ] ));

        contexts.push(Context(STATE_SUBMIT,
            "Submit step #1 of 4:", [
            ActionInstantRun("Enter recipient address", "enterRecipient", STATE_SUBMIT_AMOUNT) ]));

        fargs.set("parseBalanceArgs");
        contexts.push(Context(STATE_SUBMIT_AMOUNT,
            "Submit step #2 of 4:", [
            ActionInstantRun("", "queryBalance", STATE_CURRENT),
            ActionPrintEx("", "Enter amount of tokens to transfer ( must be < {}.{}):", true, fargs, STATE_CURRENT),
            ActionInstantRun("Enter amount:", "enterAmount", STATE_CURRENT) ] ));
        
        contexts.push(Context(STATE_SUBMIT_BOUNCE,
            "Submit step #3 of 4:", [
            ActionInstantRun("Checking wallet balance...", "checkBalance", STATE_CURRENT),
            ActionRun("Transfer to existing account?", "enableBounce", STATE_SUBMIT_SEND),
            ActionRun("Transfer to new account?", "disableBounce", STATE_SUBMIT_SEND)
        ]));
        
        fargs.set("parseTransactionInfo");
        contexts.push(Context(STATE_SUBMIT_SEND,
            "Submit step #4 of 4:\nAre you sure?", [
            ActionPrintEx("", " recipient: {}\n amount: {}.{}\n bounce: {}", true, fargs, STATE_CURRENT),
            ActionSendMsg("Yes", "sendSubmitMsg", "sign=by_user", STATE_PRE_MAIN),
            ActionPrint  ("No", "Ok, no problem.", STATE_PRE_MAIN) ] ));

        contexts.push(Context(STATE_DEPLOY,
            "Deploy wallet: step #1 of 6:\nEnter path to wallet image file\n(use SafeMultisigWallet.tvc or SetcodeMultisigWallet.tvc only):",
            [ setAttrs(ActionRun("", "enterImageFilename", STATE_CURRENT), "instant") ] ));

        contexts.push(Context(STATE_DEPLOY_STEP2,
            "Deploy wallet: step #2 of 6:\nAt this step you need to have a keypair that will be used to generate a unique address of your wallet and to sign deploy transaction.\nUse some external tool (e.g. tonos-cli) to generate keypair if you still don't have one.",
          [ ActionRun  ("Enter deploy public key", "enterDeployPublicKey", STATE_DEPLOY_STEP3),
            ActionPrint("Quit", "Quit", STATE_ZERO) ] ));

        contexts.push(Context(STATE_DEPLOY_STEP3,
            "Deploy wallet: step #3 of 6:\nEnter a number of wallet custodians\n(Custodian is a person who can submit and confirm transactions in your wallet):",
          [ ActionInstantRun("", "enterCustodianCount", STATE_DEPLOY_STEP4) ] ));

        contexts.push(Context(STATE_DEPLOY_STEP4,
            "Deploy wallet: step #4 of 6:\nNot all custodians must confirm all transctions. Enter a minimal number of custodians who should confirm a transaction before it will be executed. This value must be less then the total number of custodians.",
          [ ActionInstantRun("", "enterRequiredConfirmations", STATE_DEPLOY_STEP5) ] ));

        contexts.push(Context(STATE_DEPLOY_STEP5,
            "Deploy wallet: step #5 of 6:", [
            ActionInstantRun("enter custodian public keys", "enterKeys", STATE_DEPLOY_STEP5),
            ActionInstantPrint("", "Done", STATE_DEPLOY_STEP6) ] ));

        contexts.push(Context(STATE_DEPLOY_STEP6,
            "Deploy wallet: step #6 of 6:\nPlease, confirm wallet configuration. Is it ok?", [
             Action("", "multisig {}/{}\naddress: {}\nImportant: send some tokens to this address before you start deploy.\nIf you cannot do it right now then remember the address and come back to me later.\nnumber of custodians: {}\nnumber of required confirmations: {}\ndeploy public key: {}\ncustodian keys:", 
                ACTION_PRINT, "instant,fargs=getDeployArgs", STATE_DEPLOY_STEP6, empty),
            Action("", "printCustodianKeys", ACTION_RUN_ACTION, "instant", STATE_DEPLOY_STEP6, empty),  
            ActionSendMsg("Yes - let's deploy the wallet", "sendConstructorMsg", "sign=by_user", STATE_ZERO),
            ActionGoto("No", STATE_ZERO) ] ));
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Multisig DeBot";
        semver = (1 << 8) | 3;
    }

    function quit() public override accept { }

    uint32 constant ERROR_ZERO_ADDRESS = 1001;
    uint32 constant ERROR_AMOUNT_TOO_LOW = 1002;
    uint32 constant ERROR_TOO_MANY_CUSTODIANS = 1003;
    uint32 constant ERROR_INVALID_CONFIRMATIONS = 1004;
    uint32 constant ERROR_AMOUNT_TOO_BIG = 1005;

    function getErrorDescription(uint32 error) public pure override returns (string desc) {
        if (error == ERROR_ZERO_ADDRESS) {
            return "recipient address can't be zero";
        } else if (error == ERROR_AMOUNT_TOO_LOW) {
            return "amount must be greater or equal than 0.001 tons";
        } else if (error == ERROR_TOO_MANY_CUSTODIANS) {
            return "custodian count must be less than 32";
        } else if (error == ERROR_INVALID_CONFIRMATIONS) {
            return "number of confirmations must be less than number of custodians";
        } else if (error == ERROR_AMOUNT_TOO_BIG) {
            return "amount is bigger than wallet balance";
        }
        return "unknown exception";
    }

    /*
     *  Helpers
     */

    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }

    /*
     *  Send message handlers
     */

    function sendConfirmMsg() public view accept returns (address dest, TvmCell body) {
        dest = m_target.get();
        body = tvm.encodeBody(IMultisig.confirmTransaction, m_curTxnId);
    }

    function sendSubmitMsg() public accept view returns (address dest, TvmCell body) {
        dest = m_target.get();
        body = tvm.encodeBody(IMultisig.submitTransaction, 
            m_txn.dest, m_txn.amount, m_txn.bounce, false, empty
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

    /*
     *   Callback functions
     */

    function setCurrentTxnId(TvmCell misc) public accept {
        m_curTxnId = misc.toSlice().decode(uint64);
    }
 
    function setPendingTxns(Transaction[] transactions) public accept {
        m_pendingTxns = transactions;
    }

    function setCustodians(CustodianInfo[] custodians) public accept {
        m_custodians = custodians;
    }

    /*
     *   Getter functions for print actions
     */

    function parseTxnDetails() public accept
        returns (uint32 utime0, uint32 number1, uint8 number2, uint8 number3, uint256 param4, uint16 param5) {
        for( uint i = 0; i < m_pendingTxns.length; i++) {
            if (m_curTxnId == m_pendingTxns[i].id) {
                Transaction txn = m_pendingTxns[i];
                uint32 createdAt = uint32(txn.id >> 32);
                return (createdAt, 60 - (uint32(now) - createdAt + 59) / 60, 
                    txn.signsReceived, txn.signsRequired, txn.creator, txn.sendFlags);
            }
        }
        return (0, 0, 0, 0, 0, 0);
    }

    function parseTxnArgs(TvmCell misc) public accept
        returns (uint64 param0, address param1, uint128 number2, uint128 number3) {
        uint128 amount;
        (param0, param1, amount) = misc.toSlice().decode(uint64, address, uint128);
        (number2, number3) = tokens(amount);
    }

    function parseTxnCount(TvmCell misc) public accept returns (uint64 number0) {
        number0 = misc.toSlice().decode(uint64);
    }

    function parseCustodians(TvmCell misc) public accept returns (uint8 number0, uint256 param1) {
        (number0, param1) = misc.toSlice().decode(uint8, uint256);
    }
    
    /*
     *   Compound actions - returns arrray of subactions
     */

    function fetchTransactions() public accept returns (Action[] actions) {
        Action act0 = ActionPrint("", "Wallet has no pending transactions", STATE_CURRENT);
        act0.attrs = "instant";

        if (m_pendingTxns.length != 0) {
            TvmBuilder arg;
            arg.store(uint64(m_pendingTxns.length));
            act0.name = "Wallet has {} pending transaction(s)";
            act0.attrs = "instant,fargs=parseTxnCount";
            act0.misc = arg.toCell();
        }

        actions.push(act0);

        for (uint i = 0; i < m_pendingTxns.length; i++) {
            Transaction txn = m_pendingTxns[i];
            Action act = ActionPrint(
                "transaction ", "id: {}, recipient: {}, amount: {}.{} tokens",
                STATE_CURRENT);
            TvmBuilder misc;
            misc.store(txn.id, txn.dest, txn.value);            
            act.misc = misc.toCell();
            act.attrs = "instant,fargs=parseTxnArgs";
            actions.push(act);

            TvmBuilder txnIdBuilder;
            txnIdBuilder.store(txn.id);
            TvmCell txnIdCell = txnIdBuilder.toCell();

            act = ActionRun("Confirm", "setCurrentTxnId", STATE_CONFIRM);
            act.misc = txnIdCell;
            actions.push(act);

            act = ActionRun("Details", "setCurrentTxnId", STATE_DETAILS);
            act.misc = txnIdCell;
            actions.push(act);
        }
    }

    function fetchCustodians() public accept returns (Action[] actions) {
        mapping (uint8 => uint256) sortedCustodians;

        for(uint i = 0; i < m_custodians.length; i++) {
            CustodianInfo custody =  m_custodians[i];
            sortedCustodians[custody.index] = custody.pubkey;
        }

        optional(uint8, uint256) next = sortedCustodians.min();
        while (next.hasValue()) {
            (uint8 index, uint256 key) = next.get();
            Action act = ActionPrint("", "#{}: {}", STATE_CUSTODIANS);
            act.attrs = "instant,fargs=parseCustodians";
            TvmBuilder ctx;
            ctx.store(index, key);
            act.misc = ctx.toCell();
            actions.push(act);
            next = sortedCustodians.next(index);
        }
    }

    /*
     *    Input functions
     */ 

    function enterTargetAddress(address target) public accept {
		require(target != address(0), ERROR_ZERO_ADDRESS);
        m_target.set(target);
        m_options |= DEBOT_TARGET_ADDR;
    }

    function enterRecipient(address recipient) public accept {
        require(recipient != address(0), ERROR_ZERO_ADDRESS);
		m_txn.dest = recipient;
    }

    function setRealAmount(uint128 arg1) public accept {
        require(arg1 >= 1e6, ERROR_AMOUNT_TOO_LOW);
		m_txn.amount = arg1;
    }

    function enterAmount(string amount) public accept returns (Action[] actions) {
        optional(string) none;
        actions = [ 
            callEngine("convertTokens", amount, "setRealAmount", none),
            setAttrs(ActionGoto("", STATE_SUBMIT_BOUNCE), "instant") 
        ];
    }

    function enableBounce() public accept {
		m_txn.bounce = true;
    }

    function disableBounce() public accept {
		m_txn.bounce = false;
    }

    function queryBalance() public view accept returns (Action[] actions) {
        optional(string) argsGetter;
        argsGetter.set("getTargetAddress");
        actions = [ callEngine("getBalance", "", "setTargetBalance", argsGetter) ];
    }

    function setTargetBalance(uint128 arg1) public accept {
        m_balance = arg1;
    }

    function parseBalanceArgs() public accept returns (uint128 number0, uint128 number1) {
        (number0, number1) =tokens(m_balance);
    }

    function getTargetAddress() public accept returns (address addr) {
        addr = m_target.get();
    }

    function parseTransactionInfo() public accept returns (
        address param0, uint64 number1, uint64 number2, string str3
    ) {
        param0 = m_txn.dest;
        (number1, number2) = tokens(m_txn.amount);
        str3 = m_txn.bounce ? "yes" : "no";
    }

    function checkBalance() public accept {
        require(m_balance > m_txn.amount, ERROR_AMOUNT_TOO_BIG);
    }

    /*
     *   `Deploy new wallet` actions
     */

    function enterImageFilename(string filename) public accept returns (Action[] actions) {
        optional(string) none;
        actions = [ 
            callEngine("loadBocFromFile", filename, "setWalletTvc", none),
            setAttrs(ActionGoto("", STATE_DEPLOY_STEP2), "instant") 
        ];
    }

    function setWalletTvc(TvmCell arg1) public accept {
        m_deployData.stateInit = arg1;
    }

    function enterDeployPublicKey(uint256 pubkey) public accept {
        m_deployData.pubkey = pubkey;
    }

    function enterCustodianCount(uint8 number) public accept {
        require(number >= 1 && number <= 32, ERROR_TOO_MANY_CUSTODIANS);
        m_deployData.custodians = number;
    }

    function enterRequiredConfirmations(uint8 number) public accept {
        require(number <= m_deployData.custodians, ERROR_INVALID_CONFIRMATIONS);
        m_deployData.reqConfirms = number;
    }

    function enterKeys() public accept returns (Action[] actions) {
        m_deployData.custodianKeys = new uint256[](0);
        for (uint8 i = 0; i < m_deployData.custodians; i++) {
            Action act1 = ActionPrint("", "Enter public key {} of {}:", STATE_CURRENT);
            act1.attrs = "instant,fargs=getPubkeyIndex";
            TvmBuilder b;
            b.store(i);
            act1.misc = b.toCell();
            actions.push(act1);

            Action act2 = ActionRun("", "enterOneKey", STATE_CURRENT);
            act2.attrs = "instant";
            actions.push(act2);
        }
    }

    function getPubkeyIndex(TvmCell misc) public accept returns (uint8 number0, uint8 number1) {
        number0 = misc.toSlice().decode(uint8) + 1;
        number1 = m_deployData.custodians;
    }

    function enterOneKey(uint256 pubkey) public accept {
        m_deployData.custodianKeys.push(pubkey);
    }

    function printCustodianKeys() public accept returns (Action[] actions) {
        for (uint8 i = 0; i < m_deployData.custodians; i++) {
            TvmBuilder b;
            b.store(i);
            Action act = ActionPrint("", "custodian #{}: {}", STATE_CURRENT);
            act.attrs = "instant,fargs=getKey";
            act.misc = b.toCell();
            actions.push(act);
        }
    }

    function getKey(TvmCell misc) public accept returns (uint8 number0, uint256 param1) {
        uint i = uint(misc.toSlice().decode(uint8));
        number0 = uint8(i);
        param1 = m_deployData.custodianKeys[i];
    }

    function getDeployArgs() public accept returns (
        uint8 number0, uint8 number1, address param2, uint8 number3, uint8 number4, uint256 param5
    ) {
        TvmCell deployState = tvm.insertPubkey(m_deployData.stateInit, m_deployData.pubkey);
        param2 = address.makeAddrStd(0, tvm.hash(deployState));
        number0 = m_deployData.reqConfirms;
        number1 = m_deployData.custodians;
        number3 = number1;
        number4 = number0;
        param5 = m_deployData.pubkey; 
    }

    function sendConstructorMsg() public accept returns (address dest, TvmCell body, TvmCell state) {
        TvmCell deployState = tvm.insertPubkey(m_deployData.stateInit, m_deployData.pubkey);
        m_deployData.addr = address.makeAddrStd(0, tvm.hash(deployState));
        dest = m_deployData.addr;
        body = tvm.encodeBody(IMultisig.constructor1, m_deployData.custodianKeys, m_deployData.reqConfirms);
        state = deployState;
    }
}
