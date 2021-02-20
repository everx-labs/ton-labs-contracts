pragma ton-solidity >=0.35.0;
interface ISdk {
//account info
function getBalance(uint32 answerId, address addr) external returns (uint128 nanotokens);
function getAccountType(uint32 answerId, address addr) external returns (int8 acc_type);
function getAccountCodeHash(uint32 answerId, address addr) external returns (uint256 code_hash);
//crypto
function chacha20(uint32 answerId, bytes data, bytes nonce, uint256 key) external returns (bytes output);
//crypto utils
function signHash(uint32 answerId, uint256 hash) external returns (bytes arg1);
function genRandom(uint32 answerId, uint32 length) external returns (bytes buffer);
//7z
function compress7z(uint32 answerId, bytes uncompressed) external returns (bytes comp);
function uncompress7z(uint32 answerId, bytes compressed) external returns (bytes uncomp);
}



library Sdk {

	uint256 constant ITF_ADDR = 0x8fc6454f90072c9f1f6d3313ae1608f64f4a0660c6ae9f42c68b6a79e2a1bc4b;
	int8 constant DEBOT_WC = -31;

	function getBalance(uint32 answerId, address addr) public pure {
		address a = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(a).getBalance(answerId, addr);
	}
	function getAccountType(uint32 answerId, address addr) public pure {
		address a = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(a).getAccountType(answerId, addr);
	}
	function getAccountCodeHash(uint32 answerId, address addr) public pure {
		address a = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(a).getAccountCodeHash(answerId, addr);
	}

	function chacha20(uint32 answerId, bytes data, bytes nonce, uint256 key) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).chacha20(answerId, data, nonce, key);
	}

	function signHash(uint32 answerId, uint256 hash) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).signHash(answerId, hash);
	}
	function genRandom(uint32 answerId, uint32 length) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).genRandom(answerId, length);
	}

	function compress7z(uint32 answerId, bytes uncompressed) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).compress7z(answerId, uncompressed);
	}
	function uncompress7z(uint32 answerId, bytes compressed) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).uncompress7z(answerId, compressed);
	}

}

contract SdkABI is ISdk {
//account info
function getBalance(uint32 answerId, address addr) external override returns (uint128 nanotokens) {}
function getAccountType(uint32 answerId, address addr) external override returns (int8 acc_type) {}
function getAccountCodeHash(uint32 answerId, address addr) external override returns (uint256 code_hash) {}
//crypto
function chacha20(uint32 answerId, bytes data, bytes nonce, uint256 key) external override returns (bytes output) {}
//crypto utils
function signHash(uint32 answerId, uint256 hash) external override returns (bytes arg1) {}
function genRandom(uint32 answerId, uint32 length) external override returns (bytes buffer) {}
//7z
function compress7z(uint32 answerId, bytes uncompressed) external override returns (bytes comp) {}
function uncompress7z(uint32 answerId, bytes compressed) external override returns (bytes uncomp) {}
}