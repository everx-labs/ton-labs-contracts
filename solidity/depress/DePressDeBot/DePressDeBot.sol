pragma ton-solidity ^0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "Debot.sol";
import "itf/Sdk.sol";
import "itf/Terminal.sol";
import "itf/Base64.sol";
import "itf/Menu.sol";
import "itf/Msg.sol";
import "Upgradable.sol";
import "Transferable.sol";

abstract contract ADePress {
    constructor(mapping(uint256 => bool) keymembers, uint256 owner) public {}
    function getInfo() public returns(bytes text, bytes[] publications, uint256 signkey, uint256 enckey, uint32 nonce) {}
    function setText(bytes text, uint32 nonce) public {}
    function addPublication(bytes pub, uint32 nonce) public {}
    function setEncryptionKey(uint256 key) public {}
}

contract DePressDebot is Debot, Upgradable, Transferable{

    /*
        Storage
    */

    struct DePressInfo
    {
        bytes text; 
        bytes[] publications; 
        uint256 signkey; 
        uint256 enckey;        
        uint32 nonce;
    }

    TvmCell depressContractCode;
    DePressInfo m_info;
    uint32 m_tmpNonce;

    string m_seedphrase;
    uint256 m_masterPubKey;
    uint256 m_masterSecKey;
    uint256 m_curPubKey;
    uint256 m_curSecKey;
    address m_curAddress;

    uint32 m_curKeyIndex;
    uint32 m_maxKeyIndex;

    uint32 m_curFindBehavior;
    MenuItem[] m_listMenu;
    TvmCell m_extMsg;

    mapping(uint256 => bool) m_keyMembers;

    /*
     *   Init functions
     */

    constructor() public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        init(0,"", "", address(0));
        m_maxKeyIndex = 1;
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
        Menu.select("","At this step you need to have a seed phrase that will be used to submit and verify your work to DePress contracts.\nDon't use the seed phrase you already have.\nDon't use DePress seed phrase anywhere else.",[ 
            MenuItem("Generate a seed phrase for me","",tvm.functionId(menuGenSeedPhrase)),
            MenuItem("I have the seed phrase","",tvm.functionId(menuEnterSeedPhrase)),
            MenuItem("Quit","",0)
        ]);
    }

    function getVersion() public override returns (string name, uint24 semver) {
        name = "DePress DeBot";
        semver = (1 << 8) | 5;
    }

    function quit() public override { }
    /*
     *  Helpers
     */

    function menuGenSeedPhrase(uint32 index) public {
        Sdk.mnemonicFromRandom(tvm.functionId(showMnenminic),1,12);
    }
    function showMnenminic(string phrase) public {
        string str = "Generated phrase > ";
        str.append(phrase);
        str.append("\nWarning! Please don't forget it, otherwise you will not be able to edit your submission!\n");
        Terminal.print(0,str);
        menuEnterSeedPhrase(0);
    }

    function menuEnterSeedPhrase(uint32 index) public {
        Terminal.inputStr(tvm.functionId(checkSeedPhrase),"Enter your seed phrase",false);
    }
    function checkSeedPhrase(string value) public {
        m_seedphrase = value;
        Sdk.mnemonicVerify(tvm.functionId(verifySeedPhrase),m_seedphrase);
    }
    function verifySeedPhrase(bool valid) public {
        if (valid){
            getMasterKeysFromMnemonic(m_seedphrase);
        }else{
            Terminal.print(0,"Error: not valid seed phrase! (try to enter it without quotes or generate a new one)");
            start();
        }
    }

    function getMasterKeysFromMnemonic(string phrase) public {
        Sdk.hdkeyXprvFromMnemonic(tvm.functionId(getMasterKeysFromMnemonicStep1),phrase);
    }
    function getMasterKeysFromMnemonicStep1(string xprv) public {
        string path = "m/44'/396'/0'/0/0";
        Sdk.hdkeyDeriveFromXprvPath(tvm.functionId(getMasterKeysFromMnemonicStep2), xprv, path);
    }
    function getMasterKeysFromMnemonicStep2(string xprv) public {
        Sdk.hdkeySecretFromXprv(tvm.functionId(getMasterKeysFromMnemonicStep3), xprv);
    }
    function getMasterKeysFromMnemonicStep3(uint256 sec) public {
        Sdk.naclSignKeypairFromSecretKey(tvm.functionId(getMasterKeysFromMnemonicStep4), sec);
    }   
    function getMasterKeysFromMnemonicStep4(uint256 sec, uint256 pub) public {
        m_masterPubKey = pub;
        m_masterSecKey = sec;
        mainMenu(0);
    }

    function mainMenu(uint32 index) public {
        Menu.select("","",[ 
            MenuItem("Add DePress","",tvm.functionId(menuAddDePress)),
            MenuItem("Edit DePress","",tvm.functionId(menuListDePress)),
            MenuItem("Quit","",0)
        ]);
    }
    function menuAddDePress(uint32 index) public {
        m_curKeyIndex = m_maxKeyIndex;
        m_curFindBehavior = tvm.functionId(findNextAddressStep6);
        findNextAddress();
    }

    function menuListDePress(uint32 index) public {
        m_curKeyIndex = 1;        
        m_curFindBehavior = tvm.functionId(findNextAddressForList);
        m_listMenu = new MenuItem[](0);
        findNextAddress();
    }

    function menuSelectDePress(uint32 index) public {
        m_curKeyIndex = index+1;        
        m_curFindBehavior = tvm.functionId(findNextAddressForSelect);
        findNextAddress();
    }

    function findNextAddress() public {
        Sdk.hdkeyXprvFromMnemonic(tvm.functionId(findNextAddressStep1),m_seedphrase);
    }
    function findNextAddressStep1(string xprv) public {
        string path = "m/44'/396'/0'/0/"+string(m_curKeyIndex);
        Sdk.hdkeyDeriveFromXprvPath(tvm.functionId(findNextAddressStep2), xprv, path);
    }
    function findNextAddressStep2(string xprv) public {
        Sdk.hdkeyDeriveFromXprv(tvm.functionId(findNextAddressStep3), xprv,0,true);
    }
    function findNextAddressStep3(string xprv) public {
        Sdk.hdkeySecretFromXprv(tvm.functionId(findNextAddressStep4), xprv);
    }
    function findNextAddressStep4(uint256 sec) public {
        Sdk.naclSignKeypairFromSecretKey(tvm.functionId(findNextAddressStep5), sec);
    }   
    function findNextAddressStep5(uint256 sec, uint256 pub) public {
        m_curPubKey = pub;
        m_curSecKey = sec;
        TvmCell deployState = tvm.insertPubkey(depressContractCode, m_curPubKey);
        m_curAddress = address.makeAddrStd(0, tvm.hash(deployState));
        Sdk.getAccountType(m_curFindBehavior, m_curAddress);
    }
    function findNextAddressStep6(int8 acc_type) public {             
        if ((acc_type==-1)||(acc_type==0)) {
            deployToCurAddress();
        } else {
            m_curKeyIndex+=1;
            m_maxKeyIndex = m_curKeyIndex;
            findNextAddress();
        }
    }

    
    function findNextAddressForSelect(int8 acc_type) public { 
        if (acc_type==1){
            getCurInfo();
        }else{
            Terminal.print(0,"Critical Error! Account is not active!");
            mainMenu(0);
        }
    }

    function findNextAddressForList(int8 acc_type) public {             
        if ((acc_type==-1)||(acc_type==0)) {
            if (m_listMenu.length==0)
            {
                Terminal.print(0,"You have no DePress contracts");
                mainMenu(0);
            } else {
                m_listMenu.push(MenuItem("Back to main","",tvm.functionId(mainMenu)));
                Menu.select("","Your DePress list:",m_listMenu);
            }
        } else {
            optional(uint256) none;
            ADePress(m_curAddress).getInfo{
                abiVer: 2,
                extMsg: true,
                callbackId: tvm.functionId(setPrintInfo),
                onErrorId: 0,
                time: 0,
                expire: 0,
                sign: false,
                pubkey: none
            }();        
        }
    }

    
    function setPrintInfo(bytes text, bytes[] publications, uint256 signkey, uint256 enckey, uint32 nonce) public  {
        m_info.text = text;
        m_info.publications = publications;
        m_info.signkey = signkey;
        m_info.enckey = enckey;
        m_info.nonce = nonce;
        string str;
        if (m_info.signkey == 0){
            str = "Not signed.";
        }else {
            str = "Signed.";
        }
        m_listMenu.push(MenuItem("public key: 0x"+hexstring(m_curPubKey),str,tvm.functionId(menuSelectDePress)));
        m_curKeyIndex+=1;
        findNextAddress();
    }

    function inputKMPubKey()public {
        Terminal.inputUint(tvm.functionId(addKMKey), "Input public key of Key Community Member who can sign your submission (in hex format starting with 0x)");
    }
    function isKmAdd(bool value)public {
        if (value)
        {
            inputKMPubKey();
        }else
        {
            Terminal.print(0,format("\nPlease send 1 ton or more to address {}",m_curAddress));
            Terminal.inputBoolean(tvm.functionId(isDeployMoneySend), "Did you send the money?");            
        }
    }
    function addKMKey(uint256 value)public {
        if (m_keyMembers.exists(value)){
            Terminal.print(0,"The key has already been added!");
        } else {
            m_keyMembers[value]=true;
        }
        Terminal.inputBoolean(tvm.functionId(isKmAdd), "Do you want to add one more Key Community Member key?");
    }


    function deployToCurAddress() public  {    
        mapping(uint256 => bool) empty;
        m_keyMembers = empty;
        inputKMPubKey();
     }

    function isDeployMoneySend(bool value) public  { 
        if (value){
            Sdk.getAccountType(tvm.functionId(getAccountTypeForDeploy), m_curAddress);
        }else{
            Terminal.print(0,'Deploy terminated!');
            start();
        }
    }
    function getAccountTypeForDeploy(int8 acc_type) public {
        if (acc_type==-1){
            checkAccountDeployBalance(0);
        } else if (acc_type==0){
            Sdk.getBalance(tvm.functionId(checkAccountDeployBalance),m_curAddress);
        }        
    }

    function checkAccountDeployBalance(uint128 nanotokens) public  {         
        if (nanotokens>=900000000){
            Terminal.inputBoolean(tvm.functionId(isGoToDeploy), "Do you want to deploy?");
        }else{
            (string str0, string str1) = tokens(nanotokens);            
            string str = format("Please send 1 ton or more to address {}",m_curAddress);
            str.append(format("\nBalance is {}.{} ton now.\n",str0,str1));
            str.append("Balance should be more than 0.9 ton to continue");
            Terminal.print(0,str);
            Terminal.inputBoolean(tvm.functionId(isDeployMoneySend), "Did you send the money?");
        }
    }
    
     function isGoToDeploy(bool value) public  {  
        if (value) {
            
            TvmCell image = tvm.insertPubkey(depressContractCode, m_curPubKey);
            optional(uint256) none;
            TvmCell deployMsg = tvm.buildExtMsg({
                abiVer: 2,
                dest: m_curAddress,
                callbackId: tvm.functionId(onSuccessDeployed),
                onErrorId: tvm.functionId(onDeployFailed),
                time: 0,
                expire: 0,
                sign: true,
                pubkey: none,
                stateInit: image,
                call: {ADePress,m_keyMembers,m_masterPubKey}
            });
            
            Msg.sendWithKeypair(tvm.functionId(onSuccessDeployed),deployMsg,m_curPubKey,m_curSecKey);
        }else{
            Terminal.print(0,"Deploy terminated!");
            start();
        }
    }

    function onSuccessDeployed() public {
        Terminal.print(tvm.functionId(getCurInfo), "Contract deployed!");
    }

    function onDeployFailed(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Deploy failed. Sdk error = {}, Error code = {}",sdkError, exitCode));
        Terminal.inputBoolean(tvm.functionId(isGoToDeploy), "Do you want to retry?");
    }

    function getCurInfo() public view {             
        optional(uint256) none;
        ADePress(m_curAddress).getInfo{
            abiVer: 2,
            extMsg: true,
            callbackId: tvm.functionId(setCurInfo),
            onErrorId: 0,
            time: 0,
            expire: 0,
            sign: false,
            pubkey: none
        }();        
    }

    function setCurInfo(bytes text, bytes[] publications, uint256 signkey, uint256 enckey, uint32 nonce) public  {
        m_info.text = text;
        m_info.publications = publications;
        m_info.signkey = signkey;
        m_info.enckey = enckey;
        m_info.nonce = nonce;
        //build menu
        editMenu();
    }


    function editMenu() public {
        if (m_info.signkey == 0)
        {
            Menu.select("","",[ 
                MenuItem("Input text","",tvm.functionId(menuInputText)),
                MenuItem("View text","",tvm.functionId(menuShowText)),
                MenuItem("Send to keymember","",tvm.functionId(menuKeymemberInfo)),
                MenuItem("Back to main","",tvm.functionId(mainMenu)),
                MenuItem("Quit","",0)
            ]);
        }else if (m_info.enckey == 0)
        {
            Menu.select("","",[ 
                MenuItem("Add publication","",tvm.functionId(menuInputPublication)),
                MenuItem("View publications","",tvm.functionId(menuShowPublications)),
                MenuItem("View Text","",tvm.functionId(menuShowText)),
                MenuItem("Set encryption key","",tvm.functionId(menuInputEncKey)),
                MenuItem("Back to main","",tvm.functionId(mainMenu)),
                MenuItem("Quit","",0)
            ]);
        }else{
            Menu.select("","",[ 
                MenuItem("View publications","",tvm.functionId(menuShowPublications)),
                MenuItem("View text","",tvm.functionId(menuShowText)),
                MenuItem("Back to main","",tvm.functionId(mainMenu)),
                MenuItem("Quit","",0)
            ]);
        }
    }

    
    function menuKeymemberInfo(uint32 index) public {        
        TvmBuilder b;
        b.store(m_curSecKey);
        TvmBuilder res;
        res.storeRef(b);
        TvmSlice s = res.toSlice();
        bytes buffer = s.decode(bytes);
        Base64.encode(tvm.functionId(showKeymemberInfo), buffer);
    }
    function showKeymemberInfo(string base64)public {
        string str =  "Please send this information to the Key Member:\n Public key: 0x";
        str.append(hexstring(m_curPubKey));
        str.append("\n Encryption key: ");
        str.append(base64);
        Terminal.print(tvm.functionId(editMenu),str);        
    }

    function menuInputText(uint32 index) public {
        Terminal.inputStr(tvm.functionId(inputText),"Input your text", true);
    }
    function inputText(string value) public {
        bytes nonce = "FFFF"+hexstring(m_info.nonce+1);
        Sdk.chacha20(tvm.functionId(setEncText), value, nonce, m_curSecKey);
    }
    function setEncText(bytes output) public {
        optional(uint256) none;

        m_extMsg = tvm.buildExtMsg({
            abiVer: 2,
            dest: m_curAddress,
            callbackId: tvm.functionId(onTextSuccess),
            onErrorId: tvm.functionId(onTextError),
            time: 0,
            expire: 0,
            sign: true,
            pubkey: none,
            call: {ADePress.setText,output,m_info.nonce+1}
        });
            
        Terminal.inputBoolean(tvm.functionId(isSendTransaction), "Do you want to send transaction?");
    }

    function isSendTransaction(bool value) public {
        if (value)
            Msg.sendWithKeypair(tvm.functionId(onTextSuccess),m_extMsg,m_masterPubKey,m_masterSecKey);
        else
            Terminal.print(tvm.functionId(editMenu), "Terminated!");
    }

    function onTextSuccess() public  {
        Terminal.print(tvm.functionId(getCurInfo), "Transaction succeeded!");
    }
    function onTextError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Transaction failed. Sdk error = {}, Error code = {}",sdkError, exitCode));
        Terminal.inputBoolean(tvm.functionId(isSendTransaction), "Do you want to retry?");
    }
    
    function menuShowText(uint32 index) public {
        bytes nonce = "FFFF"+hexstring(m_info.nonce);
        Sdk.chacha20(tvm.functionId(showDecText), m_info.text, nonce, m_curSecKey);
    }
    function showDecText(bytes output) public {
        string str = "Your text:\n";
        str.append(string(output));
        Terminal.print(tvm.functionId(getCurInfo), str);
    }

    function menuInputPublication(uint32 index) public {
        Terminal.inputStr(tvm.functionId(inputPublication),"Input your publication url", false);
    }
    function inputPublication(string value) public {
        m_tmpNonce = m_info.nonce+uint32(m_info.publications.length)+1;
        bytes nonce = "FFFF"+hexstring(m_tmpNonce);
        Sdk.chacha20(tvm.functionId(setEncPublication), value, nonce, m_curSecKey);
    }    
    function setEncPublication(bytes output) public {
        optional(uint256) none;
        m_extMsg = tvm.buildExtMsg({
            abiVer: 2,
            dest: m_curAddress,
            callbackId: tvm.functionId(onTextSuccess),
            onErrorId: tvm.functionId(onTextError),
            time: 0,
            expire: 0,
            sign: true,
            pubkey: none,
            call: {ADePress.addPublication,output,m_tmpNonce}
        });
            
        Terminal.inputBoolean(tvm.functionId(isSendTransaction), "Do you want to send transaction?");
    }
    
    function menuShowPublications(uint32 index) public {
        if (m_info.publications.length>0)
        {
            Terminal.print(0,"Your publications:");
            for (uint i = 0 ; i<m_info.publications.length-1; i++)
            {
                m_tmpNonce = m_info.nonce+uint32(i)+1;
                bytes nonce = "FFFF"+hexstring(m_tmpNonce);
                Sdk.chacha20(tvm.functionId(showFirstDecPublication), m_info.publications[i], nonce, m_curSecKey);
            }

            m_tmpNonce = m_info.nonce+uint32(m_info.publications.length-1)+1;
            bytes nonce = "FFFF"+hexstring(m_tmpNonce);
            Sdk.chacha20(tvm.functionId(showLastDecPublication), m_info.publications[m_info.publications.length-1], nonce, m_curSecKey);
            m_tmpNonce = 0;
        }else{
            Terminal.print(0, "You have no publications.");
            editMenu();
        }
    }
    function showFirstDecPublication(bytes output) public {
        m_tmpNonce++;
        string str = string(m_tmpNonce)+": ";
        str.append(string(output));
        Terminal.print(0,str);
    }
    function showLastDecPublication(bytes output) public {
        showFirstDecPublication(output);
        editMenu();
    }

    function menuInputEncKey(uint32 index) public {
        Terminal.inputBoolean(tvm.functionId(isInputEncKey), "!!!\nWarning!\n!!!\nAfter publishing the encryption key, you will not be able to change your submission!\nDo you want to publish your encryption key?");
    }
    function isInputEncKey(bool value) public {
        if (value)
        {
            optional(uint256) none;
            m_extMsg = tvm.buildExtMsg({
                abiVer: 2,
                dest: m_curAddress,
                callbackId: tvm.functionId(onTextSuccess),
                onErrorId: tvm.functionId(onTextError),
                time: 0,
                expire: 0,
                sign: true,
                pubkey: none,
                call: {ADePress.setEncryptionKey,m_curSecKey}
            });
            
            Terminal.inputBoolean(tvm.functionId(isSendTransaction), "Are you sure you want to send transaction?");

        } else {
            Terminal.print(tvm.functionId(editMenu), "Terminated!");
        }
    }

    function tokens(uint128 nanotokens) private pure returns (string, string) {
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

    /*
    *  Implementation of Upgradable
    */
    function onCodeUpgrade() internal override {
        tvm.resetStorage();
        m_maxKeyIndex=1;
    }
}
