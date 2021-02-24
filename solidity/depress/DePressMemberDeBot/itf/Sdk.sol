pragma ton-solidity ^0.35.0;

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
//keys
function mnemonicFromRandom(uint32 answerId, uint32 dict, uint32 wordCount)  external returns (string phrase);
function mnemonicVerify(uint32 answerId, string phrase) external returns (bool valid);
function mnemonicDeriveSignKeys(uint32 answerId, string phrase, string path) external returns (uint256 pub, uint256 sec);
//hdkey
function hdkeyXprvFromMnemonic(uint32 answerId, string phrase) external returns (string xprv);
function hdkeyDeriveFromXprv(uint32 answerId, string inXprv, uint32 childIndex, bool hardened) external returns (string xprv);
function hdkeyDeriveFromXprvPath(uint32 answerId, string inXprv, string path)external returns (string xprv);
function hdkeySecretFromXprv(uint32 answerId, string xprv) external returns (uint256 sec);
function hdkeyPublicFromXprv(uint32 answerId, string xprv) external returns (uint256 pub);
function naclSignKeypairFromSecretKey (uint32 answerId, uint256 secret)  external returns (uint256 sec, uint256 pub);
//string
function substring(uint32 answerId, string str, uint32 start, uint32 count) external returns (string substr);
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

	function mnemonicFromRandom(uint32 answerId, uint32 dict, uint32 wordCount) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).mnemonicFromRandom(answerId, dict, wordCount);
	}
	function mnemonicVerify(uint32 answerId, string phrase) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).mnemonicVerify(answerId, phrase);
	}
	function mnemonicDeriveSignKeys(uint32 answerId, string phrase, string path) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).mnemonicDeriveSignKeys(answerId, phrase, path);
	}

	//hdkey
	function hdkeyXprvFromMnemonic(uint32 answerId, string phrase)public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).hdkeyXprvFromMnemonic(answerId, phrase);
	}
	function hdkeyDeriveFromXprv(uint32 answerId, string inXprv, uint32 childIndex, bool hardened) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).hdkeyDeriveFromXprv(answerId, inXprv, childIndex, hardened);
	}
	function hdkeyDeriveFromXprvPath(uint32 answerId, string inXprv, string path) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).hdkeyDeriveFromXprvPath(answerId, inXprv, path);
	}
	function hdkeySecretFromXprv(uint32 answerId, string xprv) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).hdkeySecretFromXprv(answerId, xprv);
	}
	function hdkeyPublicFromXprv(uint32 answerId, string xprv) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).hdkeyPublicFromXprv(answerId, xprv);
	}
	function naclSignKeypairFromSecretKey(uint32 answerId, uint256 secret) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).naclSignKeypairFromSecretKey(answerId, secret);
	}

	function substring(uint32 answerId, string str, uint32 start, uint32 count) public pure {
		address addr = address.makeAddrStd(DEBOT_WC, ITF_ADDR);
		ISdk(addr).substring(answerId, str, start, count);
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
//keys
function mnemonicFromRandom(uint32 answerId, uint32 dict, uint32 wordCount)  external override returns (string phrase) {}
function mnemonicVerify(uint32 answerId, string phrase) external override returns (bool valid) {}
function mnemonicDeriveSignKeys(uint32 answerId, string phrase, string path) external override returns (uint256 pub, uint256 sec) {}
//hdkey
function hdkeyXprvFromMnemonic(uint32 answerId, string phrase) external override returns (string xprv) {}
function hdkeyDeriveFromXprv(uint32 answerId, string inXprv, uint32 childIndex, bool hardened) external override returns (string xprv) {}
function hdkeyDeriveFromXprvPath(uint32 answerId, string inXprv, string path)external override returns (string xprv) {}
function hdkeySecretFromXprv(uint32 answerId, string xprv) external override returns (uint256 sec) {}
function hdkeyPublicFromXprv(uint32 answerId, string xprv) external override returns (uint256 pub) {}
function naclSignKeypairFromSecretKey (uint32 answerId, uint256 secret)  external override returns (uint256 sec, uint256 pub) {}
//string
function substring(uint32 answerId, string str, uint32 start, uint32 count) external override returns (string substr) {}
}
