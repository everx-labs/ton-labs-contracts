// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;

import "DePoolLib.sol";

enum RoundStep {
    // Receiving half of vesting/lock stake from participants
    PrePooling, // 0

    // Receiving stakes from participants
    Pooling, // 1

    // Waiting for election request from validator
    WaitingValidatorRequest, // 2
    // Stake has been sent to elector. Waiting for answer from elector.
    WaitingIfStakeAccepted, // 3

    // Elector has accepted round stake. Validator is candidate. Waiting validation period to know if we win elections
    WaitingValidationStart, // 4
    // DePool has tried to recover stake in validation period to know if we won elections. Waiting for elector answer
    WaitingIfValidatorWinElections, // 5
    // If CompletionReason!=Undefined, then round is completed and waiting to return/reinvest funds after the next round.
    // Else validator won elections. Waiting for the end of unfreeze period
    WaitingUnfreeze, // 6
    // Unfreeze period has been ended. Request to recover stake has been sent to elector. Waiting for answer from elector.
    WaitingReward, // 7

    // Returning or reinvesting participant stakes because round is completed
    Completing, // 8
    // All round's states are returned or reinvested
    Completed // 9
}

// Round completion statuses. Filled when round is switched to 'WaitingUnfreeze' or 'Completing' step.
enum CompletionReason {
    // Round is not completed yet
    Undefined, // 0
    // DePool is closed
    PoolClosed, // 1
    // Fake round. Used in constructor to create round1 and round2
    FakeRound, // 2
    // Validator stake is less than m_validatorAssurance
    ValidatorStakeIsTooSmall, // 3
    // Stake is rejected by elector for some reason
    StakeIsRejectedByElector, // 4
    // Reward is received from elector. Round is completed successfully
    RewardIsReceived, // 5
    // DePool has participated in elections but lost the elections
    ElectionsAreLost, // 6
    // Validator is blamed during investigation phase
    ValidatorIsPunished, // 7
    // Validator sent no request during election phase
    NoValidatorRequest // 8
}

// Describes vesting or lock stake
struct InvestParams {
    // Remaining size of vesting/lock stake
    uint64 remainingAmount;
    // Unix time in seconds of last payment
    uint64 lastWithdrawalTime;
    // Period in seconds after which `withdrawalValue` nanotons are unlocked
    uint32 withdrawalPeriod;
    // Amount of nanotons which are unlocked after `interval` second
    uint64 withdrawalValue;
    // Address of creator of vesting/lock
    address owner;
}

// Describes different stakes, that participant gets reward from
struct StakeValue {
    // Size of ordinary stake
    uint64 ordinary;
    optional(InvestParams) vesting;
    optional(InvestParams) lock;
}

// Investment round information
struct Round {
    // Sequence id (0, 1, 2, ...)
    uint64 id;
    // Supposed time when validation is started (Real time can be greater. Elections are postponed)
    uint32 supposedElectedAt;
    // Time when stake will be unfreezed. Set when validation phase is ended
    uint32 unfreeze;
    // investigation period in seconds
    uint32 stakeHeldFor;
    // validation period in seconds
    uint32 validatorsElectedFor;
    // Hash of validation set (config param 34) when round was in election phase
    uint256 vsetHashInElectionPhase;
    // Round step
    RoundStep step;
    // Status code why round is completed.
    CompletionReason completionReason;

    // Round total stake
    uint64 stake;
    // Returned stake by elector
    uint64 recoveredStake;
    // Unused stake cut-off by elector
    uint64 unused;
    // Is validator stake processed (See function returnOrReinvest)
    bool isValidatorStakeCompleted;
    // Gross reward
    uint64 grossReward;
    // Round rewards for all participants (it's not whole reward)
    uint64 rewards;
    // Number of participants in round
    uint32 participantQty;
    // Participant's stakes in round
    mapping(address => StakeValue) stakes;
    // Validator stake in round
    uint64 validatorStake;
    // Remaining part of validator stake that is not banned in case of validator slashing. Used for internal computation
    uint64 validatorRemainingStake;
    // Sum of stakes and rewards that are handled in '_returnOrReinvestForParticipant' function. Used for internal
    // computation
    uint64 handledStakesAndRewards;

    // Request from validator
    Request validatorRequest;
    // Address of elector
    address elector;
    // Address of proxy used to interact with elector
    address proxy;
}

// Represent info about last completed round
struct LastRoundInfo {
    uint32 supposedElectedAt;
    uint8 participantRewardFraction;
    uint8 validatorRewardFraction;
    uint32 participantQty;
    uint64 roundStake;
    address validatorWallet;
    uint256 validatorPubkey;
    uint64 validatorAssurance;
    uint64 reward;
    uint8 reason;
    bool isDePoolClosed;
}

contract RoundsBase {
    // roundPre0 = m_rounds[m_roundQty - 1] - pre-pooling. Helper round for adding vesting and lock stakes. When vesting/lock stake
    //                                        is added, the stake is split into two parts. First part invested into pooling round
    //                                        and second part - into pre-pooling.
    // round0    = m_rounds[m_roundQty - 2] - pooling
    // round1    = m_rounds[m_roundQty - 3] - election or validation
    // round2    = m_rounds[m_roundQty - 4] - validation or investigation
    // Algo of round rotation:
    //     delete round2
    //     round1         -> round2
    //     round0         -> round1
    //     roundPre0      -> round0
    //     createNewRound -> roundPre0
    mapping(uint64 => Round) m_rounds;
    // count of created rounds
    uint64 m_roundQty = 0;
    // Contain some useful statistic info about last completed round. mapping type is used to speedup runtime.
    mapping(bool => LastRoundInfo) lastRoundInfo;


    function isRoundPre0(uint64 id) internal inline view returns (bool) { return id == m_roundQty - 1; }
    function isRound0(uint64 id)    internal inline view returns (bool) { return id == m_roundQty - 2; }
    function isRound1(uint64 id)    internal inline view returns (bool) { return id == m_roundQty - 3; }
    function isRound2(uint64 id)    internal inline view returns (bool) { return id == m_roundQty - 4; }

    function getRoundPre0() internal inline view returns (Round) { return roundAt(m_roundQty - 1); }
    function getRound0()    internal inline view returns (Round) { return roundAt(m_roundQty - 2); }
    function getRound1()    internal inline view returns (Round) { return roundAt(m_roundQty - 3); }
    function getRound2()    internal inline view returns (Round) { return roundAt(m_roundQty - 4); }

    function setRoundPre0(Round r) internal inline { setRound(m_roundQty - 1, r); }
    function setRound0(Round r)    internal inline { setRound(m_roundQty - 2, r); }
    function setRound1(Round r)    internal inline { setRound(m_roundQty - 3, r); }
    function setRound2(Round r)    internal inline { setRound(m_roundQty - 4, r); }

    function roundAt(uint64 id) internal view returns (Round) {
        return m_rounds.fetch(id).get();
    }

    function fetchRound(uint64 id) internal view returns (optional(Round)) {
        return m_rounds.fetch(id);
    }

    function setRound(uint64 id, Round round) internal {
        m_rounds[id] = round;
    }

    function minRound() internal view returns(optional(uint64, Round)) {
        return m_rounds.min();
    }

    function nextRound(uint64 id) internal view returns(optional(uint64, Round)) {
        return m_rounds.next(id);
    }

    function _addStakes(
        Round round,
        Participant participant,
        address participantAddress,
        uint64 stake,
        optional(InvestParams) vesting,
        optional(InvestParams) lock
    )
        internal inline returns (Round, Participant)
    {
        if (stake == 0 && !vesting.hasValue() && !lock.hasValue()) {
            return (round, participant);
        }

        if (!round.stakes.exists(participantAddress)) {
            round.participantQty++;
            participant.roundQty++;
        }

        round.stake += stake;
        StakeValue sv = round.stakes[participantAddress];
        sv.ordinary += stake;

        if (vesting.hasValue()) {
            participant.haveVesting = true;
            round.stake += vesting.get().remainingAmount;
            sv.vesting = vesting;
        }

        if (lock.hasValue()) {
            participant.haveLock = true;
            round.stake += lock.get().remainingAmount;
            sv.lock = lock;
        }

        round.stakes[participantAddress] = sv;
        return (round, participant);
    }

    /// this function moves stake a size of `amount` from `source` to `destination` in the `round`
    /// returns count of transferred tokens (amount can be cut off)
    function transferStakeInOneRound(
        Round round,
        Participant sourceParticipant,
        Participant destinationParticipant,
        address source,
        address destination,
        uint64 amount,
        uint64 minStake
    )
        internal inline
        returns (
            Round, // updated round
            uint64, // transferred value
            uint64, // prev ordinary stake of source
            Participant, // updated source participant
            Participant // updated destination participant
        )
    {
        optional(StakeValue) optSourceStake = round.stakes.fetch(source);
        if (!optSourceStake.hasValue())
            return (round, 0, 0, sourceParticipant, destinationParticipant);
        StakeValue sourceStake = optSourceStake.get();
        uint64 prevSourceStake = round.stakes[source].ordinary;
        uint64 newSourceStake;
        uint64 deltaDestinationStake;
        if (sourceStake.ordinary >= amount) {
            newSourceStake = sourceStake.ordinary - amount;
            deltaDestinationStake = amount;
        } else {
            newSourceStake = 0;
            deltaDestinationStake = sourceStake.ordinary;
        }


        uint64 newDestStake = round.stakes[destination].ordinary + deltaDestinationStake;
        if ((0 < newSourceStake && newSourceStake < minStake) ||
            (0 < newDestStake && newDestStake < minStake)) {
            return (round, 0, prevSourceStake, sourceParticipant, destinationParticipant);
        }

        sourceStake.ordinary = newSourceStake;
        if (stakeSum(sourceStake) == 0) {
            --round.participantQty;
            delete round.stakes[source];
            --sourceParticipant.roundQty;
        } else {
            round.stakes[source] = sourceStake;
        }

        if (!round.stakes.exists(destination)) {
            ++round.participantQty;
            ++destinationParticipant.roundQty;
        }
        round.stakes[destination].ordinary += deltaDestinationStake;

        return (round, deltaDestinationStake, prevSourceStake, sourceParticipant, destinationParticipant);
    }

    /// Remove `participant` stake of size of `targetAmount` in the pooling round. `targetAmount` can be cut off if it
    /// exceeds real `participant` stake.
    /// @return Removed value from pooling round
    /// @return Updated participant struct
    function withdrawStakeInPoolingRound(
        Participant participant,
        address participantAddress,
        uint64 targetAmount,
        uint64 minStake
    )
        internal inline returns (uint64, Participant)
    {
        Round round = getRound0();
        optional(StakeValue) optSv = round.stakes.fetch(participantAddress);
        if (!optSv.hasValue()) {
            return (0, participant);
        }
        StakeValue sv = optSv.get();
        targetAmount = math.min(targetAmount, sv.ordinary);
        sv.ordinary -= targetAmount;
        round.stake -= targetAmount;
        if (sv.ordinary < minStake) {
            round.stake -= sv.ordinary;
            targetAmount += sv.ordinary;
            sv.ordinary = 0;
        }

        if (stakeSum(sv) == 0) {
            --round.participantQty;
            delete round.stakes[participantAddress];
            --participant.roundQty;
        } else {
            round.stakes[participantAddress] = sv;
        }
        setRound0(round);
        return (targetAmount, participant);
    }


    function stakeSum(StakeValue stakes) internal view inline returns (uint64) {
        optional(InvestParams) v = stakes.vesting;
        optional(InvestParams) l = stakes.lock;
        return
            stakes.ordinary +
            (v.hasValue() ? v.get().remainingAmount : 0) +
            (l.hasValue() ? l.get().remainingAmount : 0);
    }

    /*
     * Public Getters
     */

    // This is round struct without some fields. Used in get-methods for returning round information.
    struct TruncatedRound {
        uint64 id;
        uint32 supposedElectedAt;
        uint32 unfreeze;
        uint32 stakeHeldFor;
        uint256 vsetHashInElectionPhase;
        RoundStep step;
        CompletionReason completionReason;

        uint64 stake;
        uint64 recoveredStake;
        uint64 unused;
        bool isValidatorStakeCompleted;
        uint64 rewards;
        uint32 participantQty;
        uint64 validatorStake;
        uint64 validatorRemainingStake;
        uint64 handledStakesAndRewards;
    }

    function toTruncatedRound(Round round) internal pure returns (TruncatedRound r) {
        return TruncatedRound({
            id: round.id,
            supposedElectedAt: round.supposedElectedAt,
            unfreeze: round.unfreeze,
            stakeHeldFor: round.stakeHeldFor,
            vsetHashInElectionPhase: round.vsetHashInElectionPhase,
            step: round.step,
            completionReason: round.completionReason,

            stake: round.stake,
            recoveredStake: round.recoveredStake,
            unused: round.unused,
            isValidatorStakeCompleted: round.isValidatorStakeCompleted,
            rewards: round.rewards,
            participantQty: round.participantQty,
            validatorStake: round.validatorStake,
            validatorRemainingStake: round.validatorRemainingStake,
            handledStakesAndRewards: round.handledStakesAndRewards
        });
    }

    // Returns information about all rounds.
    function getRounds() external view returns (mapping(uint64 => TruncatedRound) rounds) {
        optional(uint64, Round) pair = minRound();
        while (pair.hasValue()) {
            (uint64 id, Round round) = pair.get();
            TruncatedRound r = toTruncatedRound(round);
            rounds[r.id] = r;
            pair = nextRound(id);
        }
    }

}
