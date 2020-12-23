pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "../Debot.sol";
import "idod.sol";

/// @title Onchain part of DoD Debot. 
/// Proxies sign requests from wallet to DoD smc.
contract DodProxy {
    // Set of signers. A temp cache of signers to prevent
    // double signing through debot. Also used as a simple way to
    // prevent spam attacks from the same addresses at a short period.
    // Important: DodDebot allow to sign DoD more than 1 time, but only when
    // cache will be reseted. 
    mapping(address => bool) public signers;
    // Number of signers in a set.
    uint public counter;
    // Address of DoD smc.
    address public dodAddress;
    // Hash used to verify income string in `transfer` function.
    uint256 public happyHash;

    // Max nunmber of signers to store before the set of signers will be reseted.
    uint constant MAX_SIGNERS = 10000;
    // Caller is not an debot owner.
    uint32 constant ERROR_INVALID_OWNER = 100;
    // Smc attaches too low value to message.
    uint32 constant ERROR_INVALID_FEE   = 102;
    // Function is called by external message.
    uint32 constant ERROR_EMPTY_SENDER  = 103;
    // Such signer is already exists in cache.
    uint32 constant ERROR_SIGNER_ALREADY_SIGNED = 104;

    modifier onlyOwner() {
        require(tvm.pubkey() == msg.pubkey(), ERROR_INVALID_OWNER);
        _;
    }

    /// @notice Debot constructor. 
    /// @param dod - address of DoD smc.
    constructor(address dod) public onlyOwner {
        tvm.accept();
        dodAddress = dod;
        happyHash = 0x85CD08D72FDC9392E1E3909D54314C222796DB95ED274A197941DC6FB33FBA63;
    }

    /// @notice Allows to sign DoD.
    function sign() public {
        require(msg.value >= 1 ton, ERROR_INVALID_FEE);
        require(msg.sender != address(0), ERROR_EMPTY_SENDER);
        require(!signers.exists(msg.sender), ERROR_SIGNER_ALREADY_SIGNED);
        
        signers[msg.sender] = true;
        counter++;

        IDoD(dodAddress).sign{flag: 64, value: 0, bounce: true}();

        if (counter >= MAX_SIGNERS) {
            delete signers;
            counter = 0;
        }
    }

    /// @notice Alllows to transfer all accumulated fees to msg sender.
    /// Sender must send a string which will be hashed to a predefined hash 
    /// to successfully execute transfer.
    function transfer(string str) public view {
        require(msg.sender != address(0), ERROR_EMPTY_SENDER);
        require(tvm.hash(bytes(str)) == happyHash, 110);
        msg.sender.transfer({ value: 1, bounce: true, flag: 128 });
    }
}

/// @title DoD Debot. Helps to sign DoD.
contract DodDebot is DodProxy, Debot, DError {

    uint8 constant STATE_PRE_MAIN = 1;
    uint8 constant STATE_PRINT_DOD = 2;
    uint8 constant STATE_SIGN_DOD = 3;
    /// Address of multisig debot.
    address m_msigDebot;
    /// Address of user multisig wallet address. 
    address m_wallet;
    /// Text of DoD.
    string m_text;
    /// Number of signs for DoD.
    uint64 m_signs;

    modifier accept() {
        tvm.accept();
        _;
    }

    /// @notice Debot constructor.
    /// @param options Flags that defines which arguments are not null.
    /// @param debotAbi DoD Debot ABI string.
    /// @param targetAbi DoD smc ABI string.
    /// @param targetAddr DoD smc address.
    constructor(
        uint8 options,
        string debotAbi,
        string targetAbi,
        address targetAddr
    ) public DodProxy(targetAddr) {
        require(tvm.pubkey() == msg.pubkey(), ERROR_INVALID_OWNER);
        tvm.accept();
        m_msigDebot = address(0x9ce35b55a00da91cfc70f649b2a2a58414d3e21ee8d1eb80dab834d442f33606);
        init(options, debotAbi, targetAbi, targetAddr);
    }

    /// @notice Debot API function. Returns array of debot contexts (menus).
    function fetch() public override returns (Context[] contexts) {
        string fireworks = "\
Congratulations!                       .\n\
              . .                     -:-             .  .  .\n\
            .'.:,'.        .  .  .     ' .           . \\ | / .\n\
            .'.;.`.       ._. ! ._.       \\          .__\\:/__.\n\
             `,:.'         ._\\!/_.                     .';`.      . ' .\n\
             ,'             . ! .        ,.,      ..======..       .:.\n\
            ,                 .         ._!_.     ||::: : | .        ',\n\
     .====.,                  .           ;  .~.===: : : :|   ..===.\n\
     |.::'||      .=====.,    ..=======.~,   |\"|: :|::::::|   ||:::|=====|\n\
  ___| :::|!__.,  |:::::|!_,   |: :: ::|\"|l_l|\"|:: |:;;:::|___!| ::|: : :|\n\
 |: :|::: |:: |!__|; :: |: |===::: :: :|\"||_||\"| : |: :: :|: : |:: |:::::|\n\
 |:::| _::|: :|:::|:===:|::|:::|:===F=:|\"!/|\\!\"|::F|:====:|::_:|: :|::__:|\n\
 !_[]![_]_!_[]![]_!_[__]![]![_]![_][I_]!//_:_\\\\![]I![_][_]!_[_]![]_!_[__]!\n\
 -----------------------------------\"---''''```---\"-----------------------\n\
 _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _\n\
                                                               FreeTON DoD\n\
__________________________________________________________________________\n\
--------------------------------------------------------------------------\n\
";
        optional(string) none;
        optional(string) signsArg;
        signsArg.set("getSignParam");
        contexts.push(Context(STATE_ZERO, 
            "Hello, I'm a DoD Debot!", [
            ActionGetMethod("", "signatures", none, "setSigns", true, STATE_CURRENT),
            ActionPrintEx("", "Number of collected signatures: {}", true, signsArg, STATE_CURRENT),
            ActionGetMethod("Read and sign DoD", "declaration", none, "setText", false, STATE_PRINT_DOD),
            ActionGoto("Quit", STATE_EXIT) ] ));

        optional(string) fargs;
        fargs.set("getTextParam");
        contexts.push(Context(STATE_PRINT_DOD,
            "Step 1 of 2:", [
            ActionPrintEx("", "{}", true, fargs, STATE_CURRENT),
            ActionGoto("Sign", STATE_SIGN_DOD),
            ActionGoto("Quit", STATE_EXIT) ] ));

        contexts.push(Context(STATE_SIGN_DOD,
            "Step 2 of 2:", [
            ActionPrintEx("", "Great! Now i will transfer your \"sign\" with 1 ton from your multisig wallet to DoD contract.", true, none, STATE_CURRENT),
            ActionInstantRun("Enter multisig wallet address:", "enterMsigAddress", STATE_CURRENT),
            setAttrs(ActionInvokeDebot("Send \"sign\" message with 1 ton", "invokeMultisigDebot", STATE_CURRENT), "instant"),
            ActionPrintEx("", fireworks, true, none, STATE_CURRENT),
            ActionGoto("Quit", STATE_EXIT) ] ));
    }

    function getVersion() public override accept returns (string name, uint24 semver) {
        name = "DoD DeBot";
        semver = (1 << 8) | 1;
    }

    function quit() public override accept { }

    uint32 constant ERROR_ZERO_ADDRESS = 101;

    function getErrorDescription(uint32 error) public pure override returns (string desc) {
        if (error == ERROR_ZERO_ADDRESS) {
            return "Wallet address cannot be zero";
        }
        return "unknown exception";
    }

    function enterMsigAddress(address wallet) public accept {
        require(wallet != address(0), 101);
        m_wallet = wallet;
    }

    function setText(string declaration) public accept {
        m_text = declaration;
    }

    function setSigns(uint64 signatures) public accept {
        m_signs = signatures;
    }

    function getTextParam() public view accept returns (string str0) {
        str0 = m_text;
    }

    function getSignParam() public view accept returns (uint64 number0) {
        number0 = m_signs;
    }

    function invokeMultisigDebot() public view accept returns (address debot, Action action) {
        debot = m_msigDebot;
        TvmCell payload = tvm.encodeBody(this.sign);
        uint64 amount = 1 ton;
        action = invokeWalletDebot(amount, payload);
    }

    function invokeWalletDebot(uint64 amount, TvmCell payload) 
        private view returns (Action action) {
        TvmBuilder args;
        args.store(m_wallet, address(this), amount, uint8(1), uint8(0), payload);
        action = ActionSendMsg("", "sendSubmitMsgEx", "instant,sign=by_user", STATE_EXIT);
        action.misc = args.toCell();
    }
}