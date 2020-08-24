// 2020 (c) TON Venture Studio Ltd

pragma solidity >0.5.0;
pragma AbiHeader expire;

import "IDePool.sol";
import "Participant.sol";

interface ITimer {
    function setTimer(uint timer) external;
}

contract DePoolHelper is Participant {
    uint constant TICKTOCK_FEE = 1e9;

    // Timer fees
    uint constant _timerRate = 400000; // 400 000 nt = 400 mct = 0,4 mt = 0,0004 t per second
    uint constant _fwdFee = 1000000; // 1 000 000 nt = 1 000 mct = 1 mt = 0,001 t
    uint constant _epsilon = 1e9;

    // Actual DePool pool contract address.
    address m_dePoolPool;
    // Array of old (closed) DePool contract addresses.
    address[] m_poolHistory;
    // Timer contract address.
    address m_timer;
    // Timer timeout.
    uint m_timeout;

    constructor(address pool) public acceptOnlyOwner {
        m_dePoolPool = pool;
    }

    modifier acceptOnlyOwner {
        require(msg.pubkey() == tvm.pubkey(), 101);
        tvm.accept();
        _;
    }

    /*
        public methods
    */

    function updateDePoolPoolAddress(address addr) public acceptOnlyOwner {
        m_poolHistory.push(m_dePoolPool);
        m_dePoolPool = addr;
    }

    /*
     * Timer functions
     */

    /// @notice Allows to set timer contract address and init timer.
    /// @param timer Address of a timer contract.
    /// Can be called only by off-chain app with owner keys.
    function initTimer(address timer, uint period) public acceptOnlyOwner {
        m_timer = timer;
        m_timeout = period;
        if (period > 0) {
            _settimer(timer, period);
        }
    }

    /// @notice Allows to init timer sending request to Timer contract.
    /// @param timer Address of a timer contract.
    function _settimer(address timer, uint period) private inline {
	    uint opex = period * _timerRate + _fwdFee * 8 + _epsilon;
        ITimer(timer).setTimer.value(opex)(period);
    }

    /// @notice Timer callback function.
    function onTimer() public {
        address timer = m_timer;
        uint period = m_timeout;
        if (msg.sender == timer) {
            IDePool(m_dePoolPool).ticktock.value(TICKTOCK_FEE)();
            if (period > 0) {
                _settimer(timer, period);
            }
        }
    }

    function manualAwake() public acceptOnlyOwner {
        IDePool(m_dePoolPool).ticktock.value(TICKTOCK_FEE)();
    }

    /*
        get methods
    */

    function getDePoolPoolAddress() public view returns (address addr) {
        addr = m_dePoolPool;
    }

    function getHistory() public view returns (address[] list) {
        list = m_poolHistory;
    }

    /*
     * Set code
     */

    function upgrade(TvmCell newcode) public acceptOnlyOwner {
        tvm.commit();
        tvm.setcode(newcode);
        tvm.setCurrentCode(newcode);
        onCodeUpgrade();
    }

    function onCodeUpgrade() private {}

    receive() external override {}
    fallback() external override {}
}
