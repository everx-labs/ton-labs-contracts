// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;

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
    function recover_stake(uint64 queryId) external functionID(0x47657424);
}