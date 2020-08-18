// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;

library Errors {
    // message sender is not owner (msg.pubkey() is wrong)
    uint constant IS_NOT_OWNER = 101;
    // not enough funds
    uint constant NOT_ENOUGH_FUNDS = 105;
    // message sender is not owner (msg.sender() is wrong)
    uint constant IS_NOT_OWNER2 = 106;
    // message sender is not proxy contract
    uint constant IS_NOT_PROXY = 107;
    // function cannot be called by external message
    uint constant IS_EXT_MSG = 108;
    // request from validator has invalid electionId
    uint constant INVALID_ELECTION_ID = 111;
    // request from validator already received in current round
    uint constant REPEATED_REQUEST = 112;
    //  msg sender is not in validator pool
    uint constant IS_NOT_VALIDATOR = 113;
    // DePool pool is closed
    uint constant DEPOOL_IS_CLOSED = 114;
    // participant with such address does not exist
    uint constant NO_SUCH_PARTICIPANT = 116;
    // depool's round does not accept requests from validator at this step
    uint constant WRONG_ROUND_STATE = 118;
    // invalid target for stake transfer or add vesting
    uint constant INVALID_ADDRESS = 119;
    // message sender is not dePool (this is not self call)
    uint constant IS_NOT_DEPOOL = 120;
    // there is no pending rounds
    uint constant NO_PENDING_ROUNDS = 121;
    // pending round is just created
    uint constant PENDING_ROUND_IS_TOO_YOUNG = 122;
    // plain transfer is forbidden. Use receiveFunds() to increase contract balance.
    uint constant TRANSFER_IS_FORBIDDEN = 123;
    // elections is not started
    uint constant NO_ELECTION_ROUND = 124;
    // invalid confirmation from elector
    uint constant INVALID_ROUND_STEP = 125;
    uint constant INVALID_QUERY_ID = 126;
    uint constant IS_NOT_ELECTOR = 127;
}

// Internal errors:
library InternalErrors {
    uint constant ERROR507 = 507;
    uint constant ERROR508 = 508;
    uint constant ERROR509 = 509;
    uint constant ERROR511 = 511;
    uint constant ERROR513 = 513;
    uint constant ERROR516 = 516;
    uint constant ERROR517 = 517;
    uint constant ERROR518 = 518;
    uint constant ERROR519 = 519;
    uint constant ERROR521 = 521;
    uint constant ERROR522 = 522;
    uint constant ERROR523 = 523;
}

library DePoolLib {

    // Describes contract who deposit stakes in DePool pool
    struct Participant {
        // Count of rounds in which participant takes a part
        uint8 roundQty;
        // Sum of all rewards from completed rounds (for logging)
        uint64 reward;
        // have vesting in any round
        bool haveVesting;
        // have lock in any round
        bool haveLock;
        // Flag whether to reinvest ordinary stakes and rewards
        bool reinvest;
        // Target tons that will be transferred to participant after rounds are completed
        // After each round this value is decreased
        uint64 withdrawValue;
    }

    // Request for elections from validator wallet.
    struct Request {
        // Random query id.
        uint64 queryId;
        // Validator's public key that will be used as validator key if validator will win elections.
        uint256 validatorKey;
        // current election id.
        uint32 stakeAt;
        // Validator's stake factor.
        uint32 maxFactor;
        // Validator's address in adnl overlay network.
        uint256 adnlAddr;
        // Ed25519 signature of above values.
        bytes signature;
    }

    uint64 constant PROXY_FEE = 0.09 ton; // 90_000_000 / 10_000 = 9_000 gas in masterchain

    uint64 constant ELECTOR_FEE = 1 ton;

    uint64 constant MAX_UINT64 = 0xFFFF_FFFF_FFFF_FFFF;
    uint32 constant MAX_TIME = 0xFFFF_FFFF; // year 2038 problem?

    uint64 constant ELECTOR_UNFREEZE_LAG = 1 minutes;
}
