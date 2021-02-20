pragma ton-solidity >=0.35.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;
import "../Debot.sol";
import "../Terminal.sol";
import "../AddressInput.sol";
import "../Sdk.sol";
import "../Menu.sol";

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
    // Destination address of gram transfer.
    address  dest;
    // Amount of nanograms to transfer.
    uint128 value;
    // Flags for sending internal message (see SENDRAWMSG in TVM spec).
    uint16 sendFlags;
    // Payload used as body of outbound internal message.
    TvmCell payload;
    // Bounce flag for header of outbound internal message.
    bool bounce;
}

struct CustodianInfo {
    uint8 index;
    uint256 pubkey;
}

interface IMultisig {
    function submitTransaction(
        address  dest,
        uint128 value,
        bool bounce,
        bool allBalance,
        TvmCell payload)
    external returns (uint64 transId);

    function confirmTransaction(uint64 transactionId) external;

    function getCustodians() external returns (CustodianInfo[] custodians);
    function getTransactions() external returns (Transaction[] transactions);
}

contract MsigDebot is Debot {

    address m_wallet;
    uint128 m_balance;
    CustodianInfo[] m_custodians;

    bool m_bounce;
    uint128 m_tons;
    address m_dest;

    constructor(string debotAbi) public {
        require(tvm.pubkey() == msg.pubkey(), 100);
        tvm.accept();
        init(DEBOT_ABI, debotAbi, "", address(0));
    }

    /*
    * Debot Basic API
    */

    function start() public override {
        Menu.select("Main menu", "Hello, i'm a multisig debot. I can help transfer tokens.", [
            MenuItem("Select account", "", tvm.functionId(selectWallet)),
            MenuItem("Exit", "", 0)
        ]);
    }

    function getVersion() public override returns (string name, uint24 semver) {
        (name, semver) = ("Multisig Debot", 1 << 16);
    }

    /*
    * Public
    */

    function selectWallet(uint32 index) public {
        index = index;
        Terminal.print(0, "Enter multisignature wallet address");
        AddressInput.select(tvm.functionId(checkWallet));
	}

    function checkWallet(address value) public {
        Sdk.getBalance(tvm.functionId(setBalance), value);
        Sdk.getAccountType(tvm.functionId(getWalletInfo), value);
        m_wallet = value;
	}

    function setBalance(uint128 nanotokens) public {
        m_balance = nanotokens;
    }

    function getWalletInfo(int8 acc_type) public {
        if (acc_type == -1)  {
            Terminal.print(0, "Wallet doesn't exist");
            return;
        }
        if (acc_type == 0) {
            Terminal.print(0, "Wallet is not initialized");
            return;
        }
        if (acc_type == 2) {
            Terminal.print(0, "Wallet is frozen");
            return;
        }

        (uint64 dec, uint64 float) = tokens(m_balance);
        Terminal.print(tvm.functionId(queryCustodians), format("Wallet balance is {}.{} tons", dec, float));
    }

    function queryCustodians() public view  {
        optional(uint256) pubkey;
        IMultisig(m_wallet).getCustodians{
            abiVer: 2,
            extMsg: true,
            sign: false,
            pubkey: pubkey,
            time: uint64(now),
            expire: 0,
            callbackId: tvm.functionId(setCustodians),
            onErrorId: 0
        }();
    }

    function setCustodians(CustodianInfo[] custodians) public {
        m_custodians = custodians;
        string str = format("Wallet has {} custodian(s)", custodians.length);
        Terminal.print(0, str);
        Terminal.inputTons(tvm.functionId(setTons), "Enter number of tokens to transfer");
        Terminal.print(0, "Select destination account");
        AddressInput.select(tvm.functionId(setDest));
        m_bounce = true;
    }

    function setTons(uint128 value) public {
        m_tons = value;
    }

    function setDest(address value) public {
        m_dest = value;
        (uint64 dec, uint64 float) = tokens(m_tons);
        string fmt = format("Transfer {}.{} tokens to account {} ?", dec, float, m_dest);
        Terminal.inputBoolean(tvm.functionId(submit), fmt);
    }

    function setBounce(bool value) public {
        m_bounce = value;
    }

    function submit(bool value) public {
        if (!value) {
            Terminal.print(0, "Ok, maybe next time. Bye!");
            return;
        }
        TvmCell empty;
        optional(uint256) pubkey = 0;
        IMultisig(m_wallet).submitTransaction{
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: pubkey,
                time: uint64(now),
                expire: 0,
                callbackId: tvm.functionId(setResult),
                onErrorId: 0
            }(m_dest, m_tons, m_bounce, false, empty);
    }

    function setResult() public {
        Terminal.print(0, "Transfer succeeded. Bye!");
    }

    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }

}