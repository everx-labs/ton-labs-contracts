// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.5.0;

interface IDePool {
    function onStakeAccept(uint64 queryId, uint32 comment, address elector) external;
    function onStakeReject(uint64 queryId, uint32 comment, address elector) external;
    function onSuccessToRecoverStake(uint64 queryId, address elector) external;
    function onFailToRecoverStake(uint64 queryId, address elector) external;
    function ticktock() external;
}