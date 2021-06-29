// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;

import "DePoolRounds.sol";

interface IDePoolInfoGetter {
    function receiveDePoolInfo(LastRoundInfo lastRoundInfo) external;
}

contract DePoolInfoGetter is IDePoolInfoGetter {
    function receiveDePoolInfo(LastRoundInfo lastRoundInfo) external override {}
}
