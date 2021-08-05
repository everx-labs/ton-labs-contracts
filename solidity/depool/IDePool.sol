// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;

interface IDePool {
    function onStakeAccept(uint64 queryId, uint32 comment, address elector) external;
    function onStakeReject(uint64 queryId, uint32 comment, address elector) external;
    function onSuccessToRecoverStake(uint64 queryId, address elector) external;
    function onFailToRecoverStake_NoFunds(uint64 queryId, address elector) external;
    function onFailToRecoverStake_TooEarly(uint64 queryId, address elector, uint32 unfreezeAt) external;
    function onReceiveElectAt(uint64 query_id, bool election_open, uint32 elect_at, address elector) external;
    function ticktock() external;
}