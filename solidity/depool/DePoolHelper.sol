// 2020 (c) TON Venture Studio Ltd

pragma solidity >0.5.0;
pragma AbiHeader expire;

import "IDePool.sol";

interface ITimer {
    function setTimer(uint timer) external;
}

contract DePoolHelper {
    uint constant TICKTOCK_FEE = 1e9;
    uint constant TIMER_FEE = 1e9;
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
        ITimer(timer).setTimer.value(TIMER_FEE)(period);
    }

    /// @notice Timer callback function.
    function onTimer() public {
        address timer = m_timer;
        uint period = m_timeout;
        if (msg.sender == timer && period > 0) {
            IDePool(m_dePoolPool).ticktock.value(TICKTOCK_FEE)();
            _settimer(timer, period);
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

    receive() external {}
    fallback() external{}
}
