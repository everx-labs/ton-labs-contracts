/* solium-disable error-reason */
pragma solidity >= 0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
pragma AbiHeader pubkey;

abstract contract Debot {

    /// @notice ACTION TYPES

    uint8 constant ACTION_EMPTY        	= 0;    // undefined action
    uint8 constant ACTION_RUN_ACTION   	= 1;    // Call debot function associated with action
    uint8 constant ACTION_RUN_METHOD   	= 2;    // Call get-method of smart contract controlled by debot.
    uint8 constant ACTION_SEND_MSG     	= 3;    // Send a message to smart contract controlled by debot.
    uint8 constant ACTION_INVOKE_DEBOT 	= 4;    // Call action from another debot
    uint8 constant ACTION_PRINT		    = 5;    // Print string to user
    uint8 constant ACTION_MOVE_TO	    = 6;    // Jumps to the context defined in 'to' field, works like a `goto` operator
    uint8 constant ACTION_CALL_ENGINE   = 10;   // Calls Dengine routine.

    // Debot options used by Dengine
    uint8 constant DEBOT_ABI            = 1;    // Debot contains its ABI
    uint8 constant DEBOT_TARGET_ABI     = 2;    // Debot contains target contract ABI
    uint8 constant DEBOT_TARGET_ADDR    = 4;    // Debot stores target contract address

    // Predefined context ids
    uint8 constant STATE_ZERO   = 0;   // initial state, before we start
    uint8 constant STATE_CURRENT= 253; // placeholder for a current context
    uint8 constant STATE_PREV   = 254; // placeholder for a previous context
    uint8 constant STATE_EXIT   = 255; // we're done
    
    struct Context {
        uint8 id;		    // Context ordinal
        string desc;        // message to be printed to the user
        Action[] actions;	// list of actions
    }

    /// @notice ACTION structure
    struct Action {
        // String that describes action step, should be printed to user
        string desc;
        // Name of debot function that runs this action
        string name;
        // Action type
        uint8 actionType;
        // Action attributes.
        // Syntax: "attr1,attr2,attr3=value,...".
        // Example: "instant,fargs=fooFunc,sign=by-user,func=foo"
        string attrs;
        // Context to transit to
	    uint8 to;
        // Action Context
        TvmCell misc;
    }
    
    uint8 m_options;
    optional(string) m_debotAbi;
    optional(string) m_targetAbi;
    optional(address) m_target;
    TvmCell empty;
    
    // debot developer should call this function from debot constructor
    function init(uint8 options, string debotAbi, string targetAbi, address targetAddr) internal {
        if (options & DEBOT_ABI != 0) m_debotAbi.set(debotAbi);
        if (options & DEBOT_TARGET_ABI != 0) m_targetAbi.set(targetAbi);
        if (options & DEBOT_TARGET_ADDR != 0) m_target.set(targetAddr);
        m_options = options;
    }

    /*
     * Public debot interface
     */

    /// @notice Invoked by DeBot Browser at debot startup. Returns array of debot contexts.
    function fetch() public virtual returns (Context[] contexts);

    function quit() public virtual;

    function getVersion() public virtual returns (string name, uint24 semver);

    function getDebotOptions() public view returns (uint8 options, string debotAbi, string targetAbi, address targetAddr) {
        debotAbi = m_debotAbi.hasValue() ? m_debotAbi.get() : "";
        targetAbi = m_targetAbi.hasValue() ? m_targetAbi.get() : "";
        targetAddr = m_target.hasValue() ? m_target.get() : address(0);
        options = m_options;
    }

    /*
     * Not implemented debot API
     */

    //function validateState(Action[] action_set) public virtual;
    //function getToken() public virtual returns (uint128 balance, string name, string symbol);

    /*
     *   Helper action functions
     */

    function ActionGoto(string desc, uint8 to) internal inline view returns (Action) {
        return Action(desc, "", ACTION_MOVE_TO, "", to, empty);
    }

    function ActionPrint(string desc, string text, uint8 to) internal inline view returns (Action) {
        return Action(desc, text, ACTION_PRINT, "", to, empty);
    }

    function ActionInstantPrint(string desc, string text, uint8 to) internal inline view returns (Action) {
        return setAttrs(ActionPrint(desc, text, to), "instant");
    }

    function ActionPrintEx(string desc, string text, bool instant, optional(string) fargs, uint8 to) 
        internal inline view returns (Action) {
        Action act = ActionPrint(desc, text, to);
        if (instant) {
            act.attrs = act.attrs + ",instant";
        }
        if (fargs.hasValue()) {
            act.attrs = act.attrs + ",fargs=" + fargs.get();
        }
        return act;
    }

    function ActionRun(string desc, string name, uint8 to) internal inline view returns (Action) {
        return Action(desc, name, ACTION_RUN_ACTION, "", to, empty);
    }

    function ActionInstantRun(string desc, string name, uint8 to) internal inline view returns (Action) {
        return setAttrs(ActionRun(desc, name, to), "instant");
    }

    function ActionGetMethod(string desc, string getmethod, optional(string) args, string callback, bool instant, uint8 to) 
        internal inline view returns (Action) {
        string attrs = "func=" + getmethod;
        if (instant) {
            attrs = attrs + ",instant";
        }
        if (args.hasValue()) {
            attrs = attrs + ",args=" + args.get();
        }
        return Action(desc, callback, ACTION_RUN_METHOD, attrs, to, empty);
    }

    function ActionSendMsg(string desc, string name, string attrs, uint8 to) internal inline view returns (Action) {
        return Action(desc, name, ACTION_SEND_MSG, attrs, to, empty);
    }

    function ActionInvokeDebot(string desc, string handlerFunc, uint8 to) internal inline view returns (Action) {
        return Action(desc, handlerFunc, ACTION_INVOKE_DEBOT, "", to, empty);
    }

    function callEngine(string func, string arg, string callback, optional(string) argsGetter) 
        internal inline view returns (Action) {
        string attrs = "func=" + callback;
        if (argsGetter.hasValue()) {
            attrs = attrs + ",args=" + argsGetter.get();
        }
        return Action(arg, func, ACTION_CALL_ENGINE, attrs, 0, empty);
    }

    function setAttrs(Action act, string attrs) internal inline pure returns (Action) {
        act.attrs = attrs;
        return act;
    }

    function setMisc(Action act, TvmCell cell) internal inline pure returns (Action) {
        act.misc = cell;
        return act;
    }
}

abstract contract DError {
    function getErrorDescription(uint32 error) public view virtual returns (string desc);
}

contract DebotABI is Debot, DError {
    function fetch() override public returns (Context[] contexts) { }
    function quit() override public {}
    function getVersion() override public returns (string name, uint24 semver) {}
    function getErrorDescription(uint32 error) public view override returns (string desc) {}
}