pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";

interface IMultisig {
    function constructor1(uint256[] owners, uint8 reqConfirms) external functionID(0x6C1E693C);
}

contract MasterLudiDebot is Debot, DError {

    // Debot context ids
    uint8 constant STATE_INPUT_OWNERS       = 1;
    uint8 constant STATE_CONFIG_WALLET      = 2;
    uint8 constant STATE_SIGN_DATA          = 3;
    uint8 constant STATE_DEPLOY             = 4;
    uint8 constant STATE_CHECK_CUSTODIANS   = 5;
    uint8 constant STATE_CALL_CONSTRUCTOR   = 6;
    uint8 constant STATE_VIEW_WALLETS       = 7;
    uint8 constant STATE_INPUT_KEYS         = 8;
    uint8 constant STATE_WALLET_SUMMARY     = 9;
    uint8 constant STATE_PRE_DEPLOY         = 10;
    uint8 constant STATE_PRE_CALL_CONSTRUCTOR = 11;

    
    uint8 constant REQUIRED_CUSTODIANS  = 3;
    uint8 constant REQUIRED_CONFIRMS    = 2;

    uint8 constant MAX_PER_TXN = 90;

    uint64 constant START_BALANCE = 0.3 ton;

    uint32 constant ERROR_INVALID_MSG_KEY = 100;
    uint32 constant ERROR_WALLET_NOT_FOUND_BY_KEY = 101;
    uint32 constant ERROR_INVALID_KEY = 102;
    uint32 constant ERROR_WALLET_ALREADY_DEPLOYED = 103;
    uint32 constant ERROR_INVALID_SIGNATURE_2 = 104;
    uint32 constant ERROR_KEY_EXISTS = 106;
    uint32 constant ERROR_INVALID_CUSTODIAN_COUNT = 107;
    uint32 constant ERROR_INVALID_CONFIRMATION_COUNT = 108;
    uint32 constant ERROR_INVALID_WALLET = 109;
    // Helper structure for accumulating constructor parameters 
    // and deploy data for new wallet 
    struct WalletConfig {
        uint256 deployKey;
        address addr;
        bool deployed;
        bool confirmed;
        uint8 custodians;
        uint8 confirmations;
        mapping(uint256 => bool) keys;
    }

    struct Participant {
        mapping(uint256 => bool) keys;
    }

    // A Copy of a structure from multisig contract
    struct CustodianInfo {
        uint8 index;
        uint256 pubkey;
    }

    /*
        Storage
    */

    TvmCell m_safeMulsitigWalletImage;
    // map of undeployed wallets: (deploykey -> Wallet config)
    mapping(uint256 => WalletConfig) m_wallets;
    uint32 m_walletCount;

    // Next vars are used only in debot's local storage (when debot is executed locally by dengine)
    // to gather info for deploy
    WalletConfig m_wallet;
    uint256 m_hash;
    uint256 m_currentKey;
    mapping(uint256 => bytes) m_signatures;

    // helper modifier
    modifier accept() {
        tvm.accept();
        _;
    }
    
    modifier acceptOnlyOwner() {
        require(tvm.pubkey() == msg.pubkey(), ERROR_INVALID_MSG_KEY);
        tvm.accept();
        _;
    }

    /*
     *   Init functions
     */

    constructor(uint8 options, string debotAbi, string targetAbi, address targetAddr) public acceptOnlyOwner {
        init(options, debotAbi, targetAbi, targetAddr);
    }

    function setTargetABI(string tabi) public acceptOnlyOwner {
        m_targetAbi.set(tabi);
        m_options |= DEBOT_TARGET_ABI;
    }

    function setABI(string dabi) public acceptOnlyOwner {
        m_debotAbi.set(dabi);
        m_options |= DEBOT_ABI;
    }

    function updateWalletTvc(TvmCell msigTvc) public acceptOnlyOwner {
        m_safeMulsitigWalletImage = msigTvc;
    }

    function addParticipants(Participant[] participants) public acceptOnlyOwner returns (uint count) {
        _addWallets(0, participants);
        count = participants.length;
    }

    function continueAddParticipants(uint start, Participant[] participants) public {
        require(msg.sender == address(this), 120);
        tvm.accept();
        _addWallets(start, participants);
    }

    function _addWallets(uint start, Participant[] participants) private {
        uint diff = participants.length - start;
        uint len = diff < MAX_PER_TXN ? diff : MAX_PER_TXN;
        for (uint i = 0; i < len; i++) {
            optional(uint256, bool) keyOpt = participants[start].keys.min();
            if (keyOpt.hasValue()) {
                (uint256 walletId, ) = keyOpt.get();
                if (!m_wallets.exists(walletId)) {
                    m_wallets[walletId].keys = participants[start].keys;
                    m_walletCount += 1;
                }
            }
            start++;
        }
        if (start < participants.length) {
            this.continueAddParticipants{value: 0.1 ton, bounce: false}(start, participants);
        }
    }

    /*
     *  Overrided Debot functions
     */

    function fetch() public override accept returns (Context[] contexts) {
        optional(string) fargs;

		// Zero state: work with existing wallet or deploy new one.
        contexts.push(Context(STATE_ZERO, 
            "Hello, validator! I am the Magister Ludi debot. I'll help you deploy your multisignature wallet.", [
            ActionPrint("Deploy wallet", "Now i need to identify you in Magister Ludi Game. Enter any of your custodian key from validator wallet in gamenet.", STATE_INPUT_OWNERS),
            ActionPrint("Quit", "Goodbye, come again when you are ready!", STATE_EXIT) ] ));

        contexts.push(Context(STATE_INPUT_OWNERS,
            "", [
            enterCustodianKeyAction(),
            ActionGoto("Exit", STATE_EXIT) ] ));

        fargs.set("getDeployArgs");
        string printWalletConfig = "Multisig {}/{}\n address: {}\n number of custodians: {}\n number of required confirmations: {}\n deploy public key: {}";
        
        contexts.push(Context(STATE_CONFIG_WALLET,
            "Ok, I found a record of your wallet on my list. Let's configure some parameters:", [
            ActionInstantRun("enter number of wallet custodians (must be >= 3):", "enterCustodianCount", STATE_CURRENT),
            ActionInstantRun("enter number of required confirmations (must be >= 2):", "enterConfirmationCount", STATE_CURRENT),
            ActionGoto("Continue", STATE_WALLET_SUMMARY) ] ));

        contexts.push(Context(STATE_WALLET_SUMMARY,
            "Wallet Summary:", [
            ActionPrintEx("", printWalletConfig, true, fargs, STATE_CURRENT),
            ActionGoto("Continue", STATE_INPUT_KEYS),
            ActionGoto("Exit", STATE_EXIT) ] ));

        contexts.push(Context(STATE_INPUT_KEYS,
            "Input Custodians:", [
            ActionInstantRun("", "enterRemainingKeys", STATE_CURRENT),
            ActionInstantPrint("", "Are you ready to proceed?", STATE_CURRENT),
            ActionGoto("Yes", STATE_SIGN_DATA),
            ActionPrint("No, return to main", "", STATE_ZERO) ] ));

        contexts.push(Context(STATE_SIGN_DATA,
            "Now you have to prove you are in possession of all these key pairs.\nI packed wallet configuration into buffer and you must sign it with N-1 keys. The last key will be used to sign deploy message.",
            [ActionInstantRun("", "signWithKeys", STATE_CURRENT),
            ActionInstantPrint("", "", STATE_PRE_DEPLOY) ] ));

        contexts.push(Context(STATE_PRE_DEPLOY,
            "Well done! I'm ready to deploy.", [
            ActionGoto("Continue", STATE_DEPLOY) ]));

        fargs.set("getDeployKey");
        contexts.push(Context(STATE_DEPLOY,
            "", [
            ActionPrintEx("", "Sign deploy message with deploy key {}:", true, fargs, STATE_CURRENT),
            ActionSendMsg("", "sendDeployWalletMsg",
                "instant,sign=by_user", STATE_PRE_CALL_CONSTRUCTOR) ] ));

        contexts.push(Context(STATE_PRE_CALL_CONSTRUCTOR,
            "Wallet deployed. Let's call wallet constructor.", [
            ActionGoto("Continue", STATE_CALL_CONSTRUCTOR) ] ));

        contexts.push(Context(STATE_CALL_CONSTRUCTOR,
            "", [
            ActionPrintEx("", "Sign constructor with deploy key {}:", true, fargs, STATE_CURRENT),
            ActionSendMsg("", "sendConstructorMsg", 
                "instant,sign=by_user", STATE_CHECK_CUSTODIANS) ] ));

        fargs.set("getWalletAddress");
        contexts.push(Context(STATE_CHECK_CUSTODIANS,
            "Great! Last check.", [
            ActionPrintEx("", "Wallet {} initialized successfully", true, fargs, STATE_CURRENT),
            Action("Checking wallet custodians", "setCustodians", ACTION_RUN_METHOD, "instant,func=getCustodians", STATE_CURRENT, empty),
            ActionInstantPrint("", "All checks are passed. Goodbye!", STATE_EXIT) ] ));
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "Magister Ludi DeBot";
        semver = (1 << 8) | 1;
    }

    function quit() public override accept { }

    function getErrorDescription(uint32 error) public pure override returns (string desc) {
        if (error == ERROR_INVALID_MSG_KEY) {
            return "Message signature is invalid. Incorrect deploy key";
        }
        if (error == ERROR_WALLET_NOT_FOUND_BY_KEY) {
            return "I cannot identify you with this key. Please, give me another custodian key";
        }
        if (error == ERROR_WALLET_ALREADY_DEPLOYED) {
            return "Sorry, wallet with this key is already deployed";
        }
        if (error == ERROR_INVALID_KEY) {
            return "Public key is not associated with your wallet"; 
        }
        if (error == ERROR_KEY_EXISTS) {
            return "Custodian with this key already exists";
        }
        if (error == ERROR_INVALID_SIGNATURE_2) {
            return "Signature check failed";
        }
        if (error == ERROR_INVALID_WALLET) {
            return "Wallet has invalid custodians";
        }
        if (error == ERROR_INVALID_CUSTODIAN_COUNT) {
            return "Number of custodians must be >= 3 and <= 32";
        }
        if (error == ERROR_INVALID_CONFIRMATION_COUNT) {
            return "Number of confirmations must be >= 2 and less than custodians count";
        }
        if (error == 51) {
            return "Constructor was already called";
        }
        return "unknown error";
    }

    /*
     *  Reusable functions
     */

    function enterCustodianKeyAction() private inline returns (Action) {
        return ActionInstantRun("Enter custodian key (0x...):", "enterContestKey", STATE_CURRENT);
    }
    
    function buildWalletState() private inline returns (TvmCell, address) {
        TvmCell state = tvm.insertPubkey(m_safeMulsitigWalletImage, m_wallet.deployKey);
        address addr = address.makeAddrStd(0, tvm.hash(state));
        return (state, addr);
    }

    /*
     *    Input functions
     */ 

    function enterContestKey(uint256 pubkey) public accept returns (Action[] actions) {
        optional(WalletConfig) walletOpt = m_wallets.fetch(pubkey);
        require(walletOpt.hasValue(), ERROR_WALLET_NOT_FOUND_BY_KEY);
        m_wallet = walletOpt.get();
        require(!m_wallet.deployed, ERROR_WALLET_ALREADY_DEPLOYED);
        require(m_wallet.keys.exists(pubkey), ERROR_INVALID_KEY);
        m_wallet.deployKey = pubkey;
        (, m_wallet.addr) = buildWalletState();
        m_target.set(m_wallet.addr);
        m_options |= DEBOT_TARGET_ADDR;
        Action act = ActionGoto("", STATE_CONFIG_WALLET);
        act.attrs = "instant";
        actions = [ act ];
    }

    function enterOneKey(uint256 pubkey) public accept {
        require(!m_wallet.keys.exists(pubkey), ERROR_KEY_EXISTS);
        m_wallet.keys[pubkey] = false;
    }

    function enterRemainingKeys() public accept returns (Action[] actions) {
        optional(string) none;
        actions.push(
            ActionPrintEx("", "Mandatory keys:", true, none, STATE_CURRENT)
        );

        uint8 qty = 0;
        optional(uint256, bool) keyOpt = m_wallet.keys.min();
        while (keyOpt.hasValue()) {
            (uint256 key, ) = keyOpt.get();

            string printStr = "custodian #" + string(qty) + ": 0x" + hexstring(key);
            actions.push(ActionInstantPrint("", printStr, STATE_CURRENT));
            qty += 1;

            keyOpt = m_wallet.keys.next(key);
        }
        uint8 mandatoryKeyCount = qty;

        uint8 remainingKeyCount = m_wallet.custodians - mandatoryKeyCount;
        if (remainingKeyCount != 0) {
            actions.push(
                ActionInstantPrint("", "Wallet will have " + string(m_wallet.custodians) + " custodians. So, you have to enter " + string(remainingKeyCount) + " more key(s)",
                    STATE_CURRENT)
            );

            for (uint8 i = 0; i < remainingKeyCount; i++) {
                actions.push(
                    ActionInstantRun("enter public key (0x...):", "enterOneKey", STATE_CURRENT)
                );
            }
        }
    }

    function enterCustodianCount(uint256 count) public accept {
        require(count >= REQUIRED_CUSTODIANS && count <= 32, ERROR_INVALID_CUSTODIAN_COUNT);
        m_wallet.custodians = uint8(count);
    }

    function enterConfirmationCount(uint256 count) public accept {
        require(count >= REQUIRED_CONFIRMS && count <= m_wallet.custodians, ERROR_INVALID_CONFIRMATION_COUNT);
        m_wallet.confirmations = uint8(count);
    }

    /*
     *  Formatting arguments getters 
     */
    
    function getWalletAddress() public accept returns (address param0) {
        param0 = m_wallet.addr;
    }

    function getDeployArgs() public accept returns (
        uint8 number0, uint8 number1, address param2, uint8 number3, uint8 number4, uint256 param5
    ) {
        param2 = m_wallet.addr;
        number0 = m_wallet.confirmations;
        number1 = m_wallet.custodians;
        number3 = number1;
        number4 = number0;
        param5 = m_wallet.deployKey; 
    }

    function getDeployKey() public accept returns (uint256 param0) {
        param0 = m_wallet.deployKey;
    }

    /*
     *    Signing actions
     */

    function signWithKeys() public accept returns (Action[] actions) {
        optional(string) args;
        args.set("getSigningHash");
        Action signAction = callEngine("signHash", "", "setSign", args);
        signAction.attrs = signAction.attrs + ",sign=by_user";
        TvmBuilder b;
        b.store(m_wallet.deployKey, m_wallet.addr);
        m_hash = tvm.hash(b.toCell());

        optional(uint256, bool) keyOpt = m_wallet.keys.min();
        (m_currentKey,) = keyOpt.get();

        while (keyOpt.hasValue()) {
            (uint256 key, ) = keyOpt.get();
            
            if (key != m_wallet.deployKey) {
                actions.push(ActionInstantPrint("", "Sign with key 0x" + hexstring(key), STATE_CURRENT));
                actions.push(signAction);
            }
            keyOpt = m_wallet.keys.next(key);
        }
    }

    function getSigningHash() public accept returns (uint256 hash) {
        hash = m_hash;
    }

    function setSign(bytes arg1) public accept {
        if (m_currentKey == m_wallet.deployKey) {
            (m_currentKey, ) = m_wallet.keys.next(m_currentKey).get();
        }

        m_signatures[m_currentKey] = arg1;
        require(tvm.checkSign(m_hash, arg1.toSlice(), m_currentKey), ERROR_INVALID_SIGNATURE_2);
        optional(uint256, bool) next = m_wallet.keys.next(m_currentKey);
        if (next.hasValue()) {
            (m_currentKey, ) = next.get();
        }
    }

    function setCustodians(CustodianInfo[] custodians) public accept {
        for(uint i = 0; i < custodians.length; i++) {
            require(m_wallet.keys.exists(custodians[i].pubkey), ERROR_INVALID_WALLET);
        }
    }

    function sendDeployWalletMsg() public accept returns (address dest, TvmCell body) {
        dest = address(this);
        body = tvm.encodeBody(
            this.deployWallet, m_wallet.addr, m_wallet.deployKey, m_signatures);
    }

    function sendConstructorMsg() public accept returns (address dest, TvmCell body) {
        dest = m_target.get();
        uint256[] keys;
        optional(uint256, bool) keyOpt = m_wallet.keys.min();
        while(keyOpt.hasValue()) {
            (uint256 key, ) = keyOpt.get();
            keys.push(key);
            keyOpt = m_wallet.keys.next(key);
        }
        body = tvm.encodeBody(IMultisig.constructor1, keys, m_wallet.confirmations);
    }

    /*
     *  On-chain functions
     */

    function deployWallet(
        address walletAddr,
        uint256 deployKey,
        mapping(uint256 => bytes) signatures
    ) public {
        require(msg.pubkey() == deployKey);
        optional(WalletConfig) walletOpt = m_wallets.fetch(deployKey);
        require(walletOpt.hasValue(), ERROR_WALLET_NOT_FOUND_BY_KEY);
        WalletConfig wallet = walletOpt.get();
        require(!wallet.deployed, ERROR_WALLET_ALREADY_DEPLOYED);

        optional(uint256, bool) keyOpt = wallet.keys.min();
        while(keyOpt.hasValue()) {
            (uint256 key, bool mandatory) = keyOpt.get();
            if (mandatory && key != deployKey) {
                require(signatures.exists(key), ERROR_INVALID_KEY);
            }
            keyOpt = wallet.keys.next(key);
        }

        tvm.accept();
        tvm.commit();

        TvmBuilder b;
        b.store(deployKey, walletAddr);
        uint256 configHash = tvm.hash(b.toCell());

        optional(uint256, bytes) signOpt = signatures.min();
        while(signOpt.hasValue()) {
            (uint256 key, bytes sign) = signOpt.get();
            require(tvm.checkSign(configHash, sign.toSlice(), key), ERROR_INVALID_SIGNATURE_2);
            if (!wallet.keys.exists(key)) {
                wallet.keys[key] = false;
            }
            signOpt = signatures.next(key);
        }

        wallet.deployKey = deployKey;
        TvmCell deployState = tvm.insertPubkey(m_safeMulsitigWalletImage, wallet.deployKey);
        wallet.addr = address.makeAddrStd(0, tvm.hash(deployState));

        TvmCell payload;
        tvm.deploy(deployState, wallet.addr, START_BALANCE, payload);
        
        wallet.deployed = true;
        m_wallets[deployKey] = wallet;
    }

    function confirmDeploy(uint256 deployKey) public {
        require(tvm.pubkey() == msg.pubkey(), ERROR_INVALID_MSG_KEY);
        optional(WalletConfig) walletOpt = m_wallets.fetch(deployKey);
        require(walletOpt.hasValue(), ERROR_WALLET_NOT_FOUND_BY_KEY);
        WalletConfig wallet = walletOpt.get();
        require(wallet.deployed, ERROR_INVALID_WALLET);
        tvm.accept();
        wallet.confirmed = true;
        m_wallets[deployKey] = wallet;
    }

    function transfer(address dest, uint128 value, bool bounce, uint16 flags) public acceptOnlyOwner {
        dest.transfer(value, bounce, flags);
    }
    
    /*
     *   Get-methods
     */

    function getWallets() public returns (uint32 walletCount, mapping(uint256 => WalletConfig) wallets) {
        walletCount = m_walletCount;
        wallets = m_wallets;
    }

}