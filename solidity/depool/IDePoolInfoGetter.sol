// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;

import "DePoolRounds.sol";

interface IDePoolInfoGetter {
    function receiveDePoolInfo(LastRoundInfo lastRoundInfo) external;
}

contract DePoolInfoGetter is IDePoolInfoGetter {
    function receiveDePoolInfo(LastRoundInfo lastRoundInfo) external override {}
}
