pragma ton-solidity ^0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";
import "itf/Sdk.sol";
import "itf/Terminal.sol";
import "itf/Base64.sol";
import "itf/Menu.sol";
import "itf/AddressInput.sol";
import "Upgradable.sol";
import "Transferable.sol";


abstract contract ADePress {
    function getInfo() public returns(bytes text, bytes[] publications, uint256 signkey, uint256 enckey, uint32 nonce) {}
    function sign() public {}
    function getKeyMembers() public returns(mapping(uint256 => bool)) {}
    function transfer(address dest, uint128 value, bool bounce, uint16 flags) public {}
}

contract DePressMemberDebot is Debot, Upgradable, Transferable{

    /*
        Storage
    */

    struct DePressInfo
    {
        bytes text; 
        bytes[] publications; 
        uint256 signkey; 
        uint256 enckey;
        uint256 ekhash;
        uint32 nonce;
    }

    TvmCell depressContractCode;
    uint256 m_pubkey;
    address m_dpAddress;
    DePressInfo m_info;
    uint256 m_enckey;
    uint32 m_tmpNonce;

    uint128 m_wtoken;
    address m_waddr;

    /*
     *   Init functions
     */

    constructor() public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        init(0,"", "", address(0));
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

    function setDePressCode(TvmCell code) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        depressContractCode = code;
    }
    
    /*
     *  Overrided Debot functions
     */

    function fetch() public override returns (Context[] contexts) {
    }

     // Entry point for new debots
    function start() public {
        Menu.select("Main menu","",[ 
            MenuItem("Sign or review","",tvm.functionId(menuSign)),
            MenuItem("Withdraw tons","",tvm.functionId(menuWithdraw)),
            MenuItem("Quit","",0)
        ]);
    }

    function getVersion() public override returns (string name, uint24 semver) {
        name = "DePress Member DeBot";
        semver = (1 << 8) | 5;
    }

    function quit() public override { }
    /*
    Withdraw
    */
     function  menuWithdraw(uint32 index) public {
        Terminal.inputUint(tvm.functionId(enterWithdrawPublicKey), "Input DePress public key (in hex format starting with 0x)");
     }

     function enterWithdrawPublicKey(uint256 value) public {
        m_pubkey = value;
        TvmCell deployState = tvm.insertPubkey(depressContractCode, m_pubkey);
        m_dpAddress = address.makeAddrStd(0, tvm.hash(deployState));
        Sdk.getAccountType(tvm.functionId(getWithdrawAccountType), m_dpAddress);
    }

    function getWithdrawAccountType(int8 acc_type) public {        

         if (acc_type==-1) {
            Terminal.print(0,"Error: Account does not exist!");
        }
        else if (acc_type==1)
        {
            Terminal.print(0,format("Contract address: {}",m_dpAddress));  
            Sdk.getBalance(tvm.functionId(getWithdrawBalance), m_dpAddress);
        } else { Terminal.print(0,"Error: Account does not active!"); }    

        
    }

    function getWithdrawBalance(uint128 nanotokens)public {     
        (string d, string f) = tokensWithdraw(nanotokens);
               
        Terminal.print(0,format("Contract balance: {}.{}",d,f));  
        Terminal.inputTons(tvm.functionId(enterWithdrawTons), "How many tons would you like to withdraw?");
    }

    function tokensWithdraw(uint128 nanotokens) private pure returns (string, string) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        string sdecimal = string(decimal);
        string sfloat = string(float);
        uint nt = 9 - sfloat.byteLength();
        for (uint i = 0 ; i<nt; i++){
            sfloat = "0"+sfloat;
        } 
        return (sdecimal, sfloat);
    }

    function enterWithdrawTons(uint128 value) public {
        m_wtoken = value;
        Terminal.print(0,"To which address do you want to withdraw tons");
        AddressInput.select(tvm.functionId(enterWithdrawAddress));
    }

    function enterWithdrawAddress(address value) public {
        m_waddr = value;
        (string d, string f) = tokensWithdraw(m_wtoken);
        Terminal.inputBoolean(tvm.functionId(withdrawBool),format("Do you want to withdraw {}.{} tons to address {}?",d,f,m_waddr));
    }

    function withdrawBool(bool value) public {
        if (value)
        {
            Terminal.print(tvm.functionId(sendTokensTransaction),"Sign transaction with your DePress seed phrase.");            
        }else{
            Terminal.print(0, "Withdraw terminated!");
            start();
        }
    }

    function sendTokensTransaction() public view {
        optional(uint256) none;
        ADePress(m_dpAddress).transfer{
            abiVer: 2,
            extMsg: true,
            callbackId: tvm.functionId(onWithdrawSuccess),
            onErrorId: tvm.functionId(onWithdrawError),
            time: 0,
            expire: 0,
            sign: true,
            pubkey: none
        }(m_waddr,m_wtoken,true,0);
    }

    function onWithdrawError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, "Transaction failed.");
        if (exitCode == 101) {
             Terminal.print(0, "Invalid key pair!" );
        } 
        Terminal.inputBoolean(tvm.functionId(withdrawBool),"Do you want to retry?");       
    }

    function onWithdrawSuccess() public  {
        Terminal.print(0, "Transaction succeeded!");
        start();
    }

    /*
     *  Helpers
     */
     function  menuSign(uint32 index) public {
        Terminal.inputUint(tvm.functionId(enterPublicKey), "Input DePress public key (in hex format starting with 0x)");
     }

     function enterPublicKey(uint256 value) public {
        m_pubkey = value;
        TvmCell deployState = tvm.insertPubkey(depressContractCode, m_pubkey);
        m_dpAddress = address.makeAddrStd(0, tvm.hash(deployState));
        Sdk.getAccountType(tvm.functionId(getAccountType), m_dpAddress);
    }

    function getAccountType(int8 acc_type) public {        
         if (acc_type==-1) {
            Terminal.print(0,"Error: Account does not exist!");
        }
        else 
        {
            Terminal.print(0,format("Contract address: {}",m_dpAddress));  
            optional(uint256) none;
            ADePress(m_dpAddress).getInfo{
                abiVer: 2,
                extMsg: true,
                callbackId: tvm.functionId(setInfo),
                onErrorId: 0,
                time: 0,
                expire: 0,
                sign: false,
                pubkey: none
            }();
        }        
    }

    function setInfo(bytes text, bytes[] publications, uint256 signkey, uint256 enckey,uint32 nonce) public {
        m_info.text = text;
        m_info.publications = publications;
        m_info.signkey = signkey;
        m_info.enckey = enckey;
        m_info.nonce = nonce;
        if (enckey!=0){
            printInfo();
        }else{//sign
            if (m_info.signkey != 0) Terminal.print(0,"!!!\nWarning: DePress is already signed!\n!!!");  
            Terminal.inputStr(tvm.functionId(enterEncryptionKey), "Enter DePress encryption key", false);
        }
    }

    function printKeyMembers(mapping(uint256 => bool) pubkeys) public {
        Terminal.print(0,"Available keys for signing:");
        optional(uint256, bool) keyOpt = pubkeys.min();
        while (keyOpt.hasValue()) {
            (uint256 key, ) = keyOpt.get();
            Terminal.print(0,"0x"+hexstring(key));
            keyOpt = pubkeys.next(key);
        }

        Terminal.inputBoolean(tvm.functionId(signInput),"Do you want to retry?");
    }

    function enterEncryptionKey(string value) public {
        Base64.decode(tvm.functionId(setRawBytes), value);
    }

    function setRawBytes(bytes data) public {
        m_enckey = data.toSlice().decode(uint256);
        bytes nonce = "FFFF"+hexstring(m_info.nonce);
        Sdk.chacha20(tvm.functionId(startSign), m_info.text, nonce, m_enckey);
    }

    function startSign(bytes output) public {
        string str = "Text:\n";
        str.append(string(output));
        Terminal.print(0, str);
        if (m_info.signkey != 0){
            Terminal.print(0,"\nSigned by 0x"+hexstring(m_info.signkey));  
            start();
        }else{
            Terminal.inputBoolean(tvm.functionId(signInput),"Do you want to sign this text?");
        }
    }

    function signInput(bool value) public {
        if (value)
        {
            optional(uint256) none;
            ADePress(m_dpAddress).sign{
                abiVer: 2,
                extMsg: true,
                callbackId: tvm.functionId(setSigned),
                onErrorId: tvm.functionId(onError),
                time: 0,
                expire: 0,
                sign: true,
                pubkey: none
            }();
        }else{
            Terminal.print(0, "Not signed!");
            start();
        }
    }

    function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, "Transaction failed.");
        if (exitCode == 104) {
             Terminal.print(0, "Your can't sign DePress with that keypair!" );
             optional(uint256) none;
             ADePress(m_dpAddress).getKeyMembers{
                abiVer: 2,
                extMsg: true,
                callbackId: tvm.functionId(printKeyMembers),
                onErrorId: 0,
                time: 0,
                expire: 0,
                sign: false,
                pubkey: none
            }();
        } else
        {
            Terminal.inputBoolean(tvm.functionId(signInput),"Do you want to retry?");
        }

    }

    function setSigned() public  {
        Terminal.print(0, "Transaction succeeded! DePress signed");
        start();
    }

    function printText(bytes output) public {
        string str = "Text:\n";
        str.append(string(output));
        Terminal.print(0, str);

        Menu.select("","",[ 
            MenuItem("Main menu","",tvm.functionId(menuMain)),
            MenuItem("Quit","",0)
        ]);
    }

    function  menuText(uint32 index) public {
        bytes nonce = "FFFF"+hexstring(m_info.nonce);
        Sdk.chacha20(tvm.functionId(printText), m_info.text, nonce, m_info.enckey);
    }

    function  menuMain(uint32 index) public {
        start();
    }

    function showFirstDecPublication(bytes output) public {
        m_tmpNonce++;
        string str = string(m_tmpNonce)+": ";
        str.append(string(output));
        Terminal.print(0,str);
    }

    function showLastDecPublication(bytes output) public {
        showFirstDecPublication(output);
        
        Menu.select("","",[ 
            MenuItem("View text","",tvm.functionId(menuText)),
            MenuItem("Main menu","",tvm.functionId(menuMain)),
            MenuItem("Quit","",0)
        ]);
    }

    function showPublications() public {
        Terminal.print(0,"Publications:");
        for (uint i = 0 ; i<m_info.publications.length-1; i++)
        {
            m_tmpNonce = m_info.nonce+uint32(i)+1;
            bytes nonce = "FFFF"+hexstring(m_tmpNonce);
            Sdk.chacha20(tvm.functionId(showFirstDecPublication), m_info.publications[i], nonce, m_info.enckey);
        }

        m_tmpNonce = m_info.nonce+uint32(m_info.publications.length-1)+1;
        bytes nonce = "FFFF"+hexstring(m_tmpNonce);
        Sdk.chacha20(tvm.functionId(showLastDecPublication), m_info.publications[m_info.publications.length-1], nonce, m_info.enckey);
        m_tmpNonce = 0;
    }

    function  printInfo()public {
        Terminal.print(0,"DePress info>");
        Terminal.print(0,"Signer public key: 0x"+hexstring(m_info.signkey));
        Terminal.print(0,"Publications count: "+string(m_info.publications.length));
        showPublications();
    }

    /*
    *  Implementation of Upgradable
    */
    function onCodeUpgrade() internal override {
        tvm.resetStorage();
    }
}