// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;

interface IProxy {

    function process_new_stake(
        uint64 queryId,
        uint256 validatorKey,
        uint32 stakeAt,
        uint32 maxFactor,
        uint256 adnlAddr,
        bytes signature,
        address elector
    ) external;

    function recover_stake_gracefully(uint64 queryId, address elector, uint32 elect_id) external;
}