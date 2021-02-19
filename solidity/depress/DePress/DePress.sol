pragma solidity >= 0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

contract DePress {

    bytes m_text;
    bytes[] m_publications;
    mapping(uint256 => bool) m_keymembers;
    uint256 m_signkey;
    uint256 m_enckey;
    uint32 m_nonce;
    uint256 m_owner;

//errors
// 101 - wrong owner keys
// 102 - no key member list
// 103 - already sign by key member
// 104 - not valid key member
// 105 - there is no any publication
// 106 - encryption key is already set
// 108 - no sign from key member
// 111 - text is empty
// 112 - wrong nonce. dublicated nonce.
    

    constructor(mapping(uint256 => bool) keymembers, uint256 owner) public {
        require(msg.pubkey() == tvm.pubkey(), 101);
        require(!keymembers.empty(), 102);
        tvm.accept();
        m_keymembers = keymembers;
        m_owner = owner;
    }

    function setText(bytes text, uint32 nonce) public {
      	require(m_owner == msg.pubkey(), 101);
    	require(m_signkey == 0, 103);
        require(nonce==(m_nonce+1),112);
        tvm.accept();
        m_text = text;
        m_nonce = nonce;
    }

    function addPublication(bytes pub, uint32 nonce) public {
        require(m_owner == msg.pubkey(), 101);
        require(m_signkey != 0, 108);
        require(m_enckey == 0, 106);
        require(nonce==(m_nonce+m_publications.length+1),112);
        tvm.accept();
        m_publications.push(pub);
    }
	
    function sign() public {
        require(m_keymembers.exists(msg.pubkey()), 104);
        require(m_signkey == 0, 103);
        require(m_text.length > 0, 111);
        tvm.accept();
        m_signkey = msg.pubkey();
    }

    function setEncryptionKey(uint256 key) public {
        require(m_owner == msg.pubkey(), 101);
        require(m_publications.length > 0, 105);
        tvm.accept();
        m_enckey = key;
    }

    function getInfo() public view returns(bytes text, bytes[] publications, uint256 signkey, uint256 enckey, uint32 nonce)
    {
        text = m_text;
        publications = m_publications;
        signkey = m_signkey;
        enckey = m_enckey;
        nonce = m_nonce;
    }

    function getKeyMembers() public view returns(mapping(uint256 => bool) pubkeys){
        pubkeys = m_keymembers;
    }    

    function transfer(address dest, uint128 value, bool bounce, uint16 flags) public view {
        require(m_owner == msg.pubkey(), 101);
        tvm.accept();
        dest.transfer(value, bounce, flags);
    }
}


