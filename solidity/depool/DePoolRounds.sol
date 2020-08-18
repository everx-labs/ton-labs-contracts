// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;

import "DePoolLib.sol";

contract RoundsBase {

    enum RoundStep {
        // Receiving stakes from participants
        Pooling,

        // Waiting for election request from validator
        WaitingValidatorRequest,
        // Stake has been send to elector. Waiting answer from elector.
        WaitingIfStakeAccepted,

        // Elector has accepted round stake. Validator is candidate. Waiting validation period to know if we win elections
        WaitingValidationStart,
        // DePool has tried to recover stake in validation period to know if we win elections. Waiting elector answer
        WaitingIfValidatorWinElections,
        // Waiting for ending of unfreeze period
        // If CompletionReason!=Undefined than round is completed and waiting to return/reinvest funds after the next round.
        // Else round win election. Waiting
        WaitingUnfreeze,
        // Unfreeze period has been ended. Request to recover stake has been sent to elector. Waiting answer from elector.
        WaitingReward,

        // Returning or reinvesting participant stakes because round is completed
        Completing,
        // All round's states are returned or reinvested
        Completed
    }

    // Round completion statuses. Filled when round is switched to 'WaitingUnfreeze' or 'Completing' step.
    enum CompletionReason {
        // Round is not completed yet
        Undefined,
        // DePool is closed
        PoolClosed,
        // Fake round. Used in constructor to create prev and 'last but 2' rounds
        FakeRound,
        // Total stake less that 'm_minRoundStake'
        TotalStakeIsTooSmall,
        // Validator stake percent of m_minRoundStake is too small
        ValidatorStakeIsTooSmall,
        // Stake is rejected by elector by some reason
        StakeIsRejectedByElector,
        // Reward is received from elector. Round is completed successfully
        RewardIsReceived,
        // DePool has been participated in elections but lost the elections
        ElectionsAreLost,
        // Validator are blamed during investigation phase
        ValidatorIsPunished,
        // Validator send no request during election phase
        NoValidatorRequest
    }

    // Describes vesting or lock stake
    struct InvestParams {
        bool isActive;
        // Size of vesting stake
        uint64 amount;
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
        // Size of usual stake
        uint64 ordinary;
        optional(InvestParams) vesting;
        optional(InvestParams) lock;
    }

    // Investment round information
    struct Round {
        // Sequence id (0, 1, 2, ...)
        uint64 id;
        // Supposed time when validation is started (Real time can be greater. Elections is postponed)
        uint32 supposedElectedAt;
        // Time when stake will be unfreezed. Set when validation phase is ended
        uint32 unfreeze;
        // Round step
        RoundStep step;
        // Status code why round is completed.
        CompletionReason completionReason;
        // Number of participants in round.
        uint32 participantQty;
        // Round total stake
        uint64 stake;
        // Participant's stakes in round
        mapping(address => StakeValue) stakes;
        // Round rewards
        uint64 rewards;
        // Request from validator
        DePoolLib.Request validatorRequest;
        // Address of elector
        address elector;
        // Hash of validation set (config param 34) when round was in election phase
        uint256 vsetHashInElectionPhase;
        // Address of proxy used to interactive with elector
        address proxy;

        // Unixtime when round is created (just for logging)
        uint32 start;
        // Unixtime when round is switch to step Completing (just for logging)
        uint32 end;
        // Unused stake cut-off by elector (just for logging)
        uint64 unused;
    }

    // m_rounds[m_roundQty - 1] - pooling
    // m_rounds[m_roundQty - 2] - election or validation
    // m_rounds[m_roundQty - 3] - validation or investigation
    mapping(uint64 => Round) m_rounds;

    // count of created rounds
    uint64 m_roundQty = 0;

    function _addStakes(
        Round round,
        DePoolLib.Participant participant,
        address participantAddress,
        uint64 stake,
        optional(InvestParams) vesting,
        optional(InvestParams) lock
    )
        internal inline returns (Round, DePoolLib.Participant)
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
            if (vesting.get().isActive) {
                round.stake += vesting.get().amount;
            }
            sv.vesting = vesting;
        }

        if (lock.hasValue()) {
            participant.haveLock = true;
            if (lock.get().isActive) {
                round.stake += lock.get().amount;
            }
            sv.lock = lock;
        }

        round.stakes[participantAddress] = sv;
        return (round, participant);
    }

    /// this function move stake a size of `amount` from `source` to `destination` in the `round`
    /// return count of transferred tokens (amount can be cut off)
    function transferStakeInOneRound(
        Round round,
        DePoolLib.Participant sourceParticipant,
        DePoolLib.Participant destinationParticipant,
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
            DePoolLib.Participant, // updated source participant
            DePoolLib.Participant // updated destination participant
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

        round.stakes[source].ordinary = newSourceStake;
        if (sumOfStakes(round.stakes[source]) == 0) {
            --round.participantQty;
            delete round.stakes[source];
            --sourceParticipant.roundQty;
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
        DePoolLib.Participant participant,
        address participantAddress,
        uint64 targetAmount,
        uint64 minStake
    )
        internal inline returns (uint64, DePoolLib.Participant)
    {
        Round round = m_rounds[m_roundQty - 1];
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

        if (sumOfStakes(sv) == 0) {
            --round.participantQty;
            delete round.stakes[participantAddress];
            --participant.roundQty;
        } else {
            round.stakes[participantAddress] = sv;
        }
        m_rounds[m_roundQty - 1] = round;
        return (targetAmount, participant);
    }


    function sumOfStakes(StakeValue stakes) internal inline returns (uint64) {
        return
            stakes.ordinary +
            (stakes.vesting.hasValue()? stakes.vesting.get().amount : 0) +
            (stakes.lock.hasValue()? stakes.lock.get().amount : 0)
            ;
    }

    /*
     * Public Getters
     */

    // This is round struct without some fields. Used in get-methods for returning round information.
    struct TruncatedRound {
        uint64 id;
        uint32 supposedElectedAt;
        uint32 unfreeze;
        RoundStep step;
        CompletionReason completionReason;
        uint32 participantQty;
        uint64 stake;
        uint64 rewards;
        uint64 unused;
        uint64 start;
        uint64 end;
        uint256 vsetHash;
    }

    function toTruncatedRound(Round round) internal pure returns (TruncatedRound) {
        return TruncatedRound(
            round.id,
            round.supposedElectedAt,
            round.unfreeze,
            round.step,
            round.completionReason,
            round.participantQty,
            round.stake,
            round.rewards,
            round.unused,
            round.start,
            round.end,
            round.vsetHashInElectionPhase
        );
    }

    function getRounds() external view returns (mapping(uint64 => TruncatedRound) rounds) {
        optional(uint64, Round) pair = m_rounds.min();
        while (pair.hasValue()) {
            (uint64 id, Round round) = pair.get();
            TruncatedRound r = toTruncatedRound(round);
            rounds[r.id] = r;
            pair = m_rounds.next(id);
        }
        return rounds;
    }

}
