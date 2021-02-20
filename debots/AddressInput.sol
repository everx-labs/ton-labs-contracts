pragma ton-solidity >=0.35.0;

interface IAddressInput {
	function select(uint32 answerId) external returns (address value);
}

library AddressInput {
    int8 constant DEBOT_WC = -31;
    uint256 constant ID = 0xd7ed1bd8e6230871116f4522e58df0a93c5520c56f4ade23ef3d8919a984653b;

    function select(uint32 answerId) public pure {
        address addr = address.makeAddrStd(DEBOT_WC, ID);
        IAddressInput(addr).select(answerId);
    }
}

contract AddressInputABI is IAddressInput {
    function select(uint32 answerId) external override returns (address value) {}
}