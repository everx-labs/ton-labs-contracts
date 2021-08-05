// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;

interface IElector {
    /// @dev Allows validator to become validator candidate
    function process_new_stake(
        uint64 queryId,
        uint256 validatorKey,
        uint32 stakeAt,
        uint32 maxFactor,
        uint256 adnlAddr,
        bytes signature
    ) external functionID(0x4E73744B);

    /// @dev Allows to get back validator's stake
    function recover_stake_gracefully(uint64 query_id, uint32 elect_id) external functionID(0x47657425);

    function get_elect_at(uint64 query_id) external functionID(0x47657426);
}