pragma solidity >= 0.6.0;
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

    function fetch() public override returns (Context[] contexts) {}

    function start() public override {
        Menu.select("Main menu", "Hello, i'm a multisig debot. I can help transfer tokens from your multisignature wallet.", [
            MenuItem("Select wallet", "", tvm.functionId(selectWallet)),
            MenuItem("Exit", "", 0)
        ]);
    }

    function quit() public override {

    }

    function getVersion() public override returns (string name, uint24 semver) {
        (name, semver) = ("Multisig Debot", 4 << 8);
    }

    /*
    * Public
    */

    function selectWallet(uint32 index) public {
        index = index;
        Terminal.print(0, "Please, enter your multisignature wallet address:");
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
            Terminal.print(0, format("Account with address {} doesn't exist", m_wallet));
        } else {
            string state = "";
            if (acc_type == 0) {
                state = "Uninit";
            } else if (acc_type == 2) {
                state = "Frozen";
            } else if (acc_type == 1) {
                state = "Active";
            }
            Terminal.print(0, "Account state: " + state);
            (uint64 dec, uint64 float) = tokens(m_balance);
            Terminal.print(0, format("Account balance: {}.{}", dec, float));
            if (state != "Active") {
                return;
            }

            optional(uint256) pubkey;
            IMultisig(m_wallet).getCustodians{
                extMsg: true,
                time: uint64(now),
                sign: false,
                pubkey: pubkey,
                expire: tvm.functionId(setCustodians)
            }();

            Terminal.inputTons(tvm.functionId(setTons), "Enter number of tokens to transfer:");
            Terminal.print(0, "Enter address of destination account:");
            AddressInput.select(tvm.functionId(setDest));
            Terminal.inputBoolean(tvm.functionId(setBounce), "Does the destination account exist?");
        }
    }

    function setCustodians(CustodianInfo[] custodians) public {
        m_custodians = custodians;
        string str = format("Wallet has {} custodian(s)", custodians.length);
        Terminal.print(tvm.functionId(submit), str);
    }

    function setTons(uint128 value) public {
        m_tons = value;
    }

    function setDest(address value) public {
        m_dest = value;
    }

    function setBounce(bool value) public {
        m_bounce = value;
    }

    function submit() public view {
        TvmCell empty;
        optional(uint256) pubkey = 0;
        IMultisig(m_wallet).submitTransaction{
                extMsg: true,
                time: uint64(now),
                sign: true,
                pubkey: pubkey,
                expire: tvm.functionId(setResult)
            }(m_dest, m_tons, m_bounce, false,  empty);
    }

    function setResult() public {
        Terminal.print(0, "Transaction succeeded. Bye!");
    }

    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }
    
}