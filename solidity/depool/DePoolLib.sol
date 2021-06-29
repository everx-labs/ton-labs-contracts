// 2020 (c) TON Venture Studio Ltd

pragma ton-solidity >= 0.46.0;

// Describes contract that deposits stakes in DePool pool
struct Participant {
    // Count of rounds in which participant takes part
    uint8 roundQty;
    // Sum of all rewards from completed rounds (for logging)
    uint64 reward;
    // count of parts of vesting stakes in the rounds
    uint8 vestingParts;
    // count of parts of lock stakes in the rounds
    uint8 lockParts;
    // Flag whether to reinvest ordinary stakes and rewards
    bool reinvest;
    // Target tons that will be transferred to participant after rounds are completed
    // After each round this value is decreased
    uint64 withdrawValue;
    // address from which vesting stake can be given for the participant
    address vestingDonor;
    // address from which lock stake can be given for the participant
    address lockDonor;
}

// Request for elections from validator wallet.
struct Request {
    // Random query id.
    uint64 queryId;
    // Validator's public key that will be used as validator key if validator wins elections.
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

library Errors {
    // message sender is not owner (msg.pubkey() is wrong)
    uint constant IS_NOT_OWNER = 101;
    // message sender is not proxy contract
    uint constant IS_NOT_PROXY = 107;
    // function cannot be called by external message
    uint constant IS_EXT_MSG = 108;
    //  msg sender is not in validator pool
    uint constant IS_NOT_VALIDATOR = 113;
    // DePool pool is closed
    uint constant DEPOOL_IS_CLOSED = 114;
    // participant with such address does not exist
    uint constant NO_SUCH_PARTICIPANT = 116;
    // message sender is not dePool (this is not self call)
    uint constant IS_NOT_DEPOOL = 120;
    // invalid confirmation from elector
    uint constant INVALID_ROUND_STEP = 125;
    uint constant INVALID_QUERY_ID = 126;
    uint constant IS_NOT_ELECTOR = 127;
    uint8 constant BAD_STAKES = 129;
    uint8 constant CONSTRUCTOR_NO_PUBKEY = 130;
    uint8 constant VALIDATOR_IS_NOT_STD = 133;
    uint8 constant BAD_PART_REWARD = 138;
    uint8 constant BAD_PROXY_CODE = 141;
    uint8 constant NOT_WORKCHAIN0 = 142;
    uint8 constant NEW_VALIDATOR_FRACTION_MUST_BE_LESS_THAN_OLD = 143;
    uint8 constant FRACTION_MUST_NOT_BE_ZERO = 144;
    uint8 constant BAD_ACCOUNT_BALANCE = 146;
    uint8 constant VALIDATOR_IS_ZERO_ADDR = 147;
    // message sender is not proxy contract
    uint constant IS_NOT_ROUND_PROXY = 148;
    uint constant BAD_MIN_STAKE_AND_ASSURANCE = 149;
}

// Internal errors:
library InternalErrors {
    uint16 constant ERROR507 = 507;
    uint16 constant ERROR508 = 508;
    uint16 constant ERROR509 = 509;
    uint16 constant ERROR511 = 511;
    uint16 constant ERROR516 = 516;
    uint16 constant ERROR517 = 517;
    uint16 constant ERROR518 = 518;
    uint16 constant ERROR519 = 519;
    uint16 constant ERROR521 = 521;
    uint16 constant ERROR522 = 522;
    uint16 constant ERROR523 = 523;
    uint16 constant ERROR524 = 524;
    uint16 constant ERROR525 = 525;
    uint16 constant ERROR526 = 526;
    uint16 constant ERROR527 = 527;
    uint16 constant ERROR528 = 528;
    uint16 constant ERROR529 = 529;
    uint16 constant ERROR530 = 530;
}

library DePoolLib {

    uint64 constant PROXY_FEE = 0.09 ton; // 90_000_000 / 10_000 = 9_000 gas in masterchain
    uint64 constant MIN_PROXY_BALANCE = 1 ton;
    uint64 constant PROXY_CONSTRUCTOR_FEE = 1 ton;
    uint64 constant DEPOOL_CONSTRUCTOR_FEE = 1 ton;

    uint64 constant ELECTOR_FEE = 1 ton;

    uint64 constant MAX_UINT64 = 0xFFFF_FFFF_FFFF_FFFF;
    uint32 constant MAX_TIME = 0xFFFF_FFFF;

    uint64 constant ELECTOR_UNFREEZE_LAG = 1 minutes;
}
