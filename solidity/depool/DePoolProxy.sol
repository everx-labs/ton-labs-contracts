// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;
import "../elector/IElector.sol";
import "IDePool.sol";
import "IProxy.sol";
import "DePoolLib.sol";

contract DePoolProxyContract is IProxy {

    uint constant ERROR_IS_NOT_DEPOOL = 102;
    uint constant ERROR_BAD_BALANCE = 103;
    uint constant ERROR_IS_NOT_VALIDATOR = 104;

    uint8 static m_id;
    address static m_dePool;
    address static m_validatorWallet;

    constructor() public {
        require(msg.sender == m_dePool, ERROR_IS_NOT_DEPOOL);
    }

    modifier onlyDePoolAndCheckBalance {
        require(msg.sender == m_dePool, ERROR_IS_NOT_DEPOOL);

        // this check is needed for correct work of proxy
        require(address(this).balance >= msg.value + DePoolLib.MIN_PROXY_BALANCE, ERROR_BAD_BALANCE);
        _;
    }

    /*
     * process_new_stake
     */

    /// @dev Allows to send validator request to run in validator elections
    function process_new_stake(
        uint64 queryId,
        uint256 validatorKey,
        uint32 stakeAt,
        uint32 maxFactor,
        uint256 adnlAddr,
        bytes signature,
        address elector
    ) external override onlyDePoolAndCheckBalance {
        IElector(elector).process_new_stake{value: msg.value - DePoolLib.PROXY_FEE}(
            queryId, validatorKey, stakeAt, maxFactor, adnlAddr, signature
        );
    }

    /// @dev Elector answer from process_new_stake in case of success.
    function onStakeAccept(uint64 queryId, uint32 comment) public functionID(0xF374484C) view {
        // Elector contract always sends 1 ton
        IDePool(m_dePool).onStakeAccept{
            value: msg.value - DePoolLib.PROXY_FEE,
            bounce: false
        }(queryId, comment, msg.sender);
    }

    /// @dev Elector answer from process_new_stake in case of error.
    function onStakeReject(uint64 queryId, uint32 comment) view public functionID(0xEE6F454C) {
        IDePool(m_dePool).onStakeReject{
            value: msg.value - DePoolLib.PROXY_FEE,
            bounce: false
        }(queryId, comment, msg.sender);
    }

    /*
     * recover_stake
     */

    /// @dev Allows to recover validator stake
    function recover_stake_gracefully(uint64 queryId, address elector, uint32 elect_id) public override onlyDePoolAndCheckBalance {
        IElector(elector).recover_stake_gracefully{value: msg.value - DePoolLib.PROXY_FEE}(queryId, elect_id);
    }

    /// @dev Elector answer from recover_stake_gracefully in case of success.
    function onSuccessToRecoverStake(uint64 queryId) public view functionID(0xF96F7324) {
        IDePool(m_dePool).onSuccessToRecoverStake{
            value: msg.value - DePoolLib.PROXY_FEE,
            bounce: false
        }(queryId, msg.sender);
    }

    function onFailToRecoverStake_NoFunds(uint64 queryId, uint32 body) public view functionID(0xFFFFFFFE) {
        body = body; // suspend warning: unused-var
        // body always equal to 0x47657425

        IDePool(m_dePool).onFailToRecoverStake_NoFunds{
            value: msg.value - DePoolLib.PROXY_FEE,
            bounce: false
        }(queryId, msg.sender);
    }

    function onFailToRecoverStake_TooEarly(uint64 queryId, uint32 unfreezeAt) public view functionID(0xFFFFFFFD) {
        IDePool(m_dePool).onFailToRecoverStake_TooEarly{
            value: msg.value - DePoolLib.PROXY_FEE,
            bounce: false
        }(queryId, msg.sender, unfreezeAt);
    }

    function withdrawExcessTons() public view {
        require(msg.sender == m_validatorWallet, ERROR_IS_NOT_VALIDATOR);
        uint128 balance = address(this).balance;
        if (balance >= 2 * DePoolLib.MIN_PROXY_BALANCE) {
            uint128 returnValue = balance - 2 * DePoolLib.MIN_PROXY_BALANCE;
            m_validatorWallet.transfer({value: returnValue, bounce: false, flag: 0});
        }
    }

    /*
     * Public Getters
     */

    function getProxyInfo() public view returns (address depool, uint64 minBalance) {
        depool = m_dePool;
        minBalance = DePoolLib.MIN_PROXY_BALANCE;
    }
}
