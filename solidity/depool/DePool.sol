// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
//pragma ignoreIntOverflow; // NOTE: delete this to check integer overflow
import "IDePool.sol";
import "IParticipant.sol";
import "DePoolBase.sol";
import "DePoolRounds.sol";

contract DePoolContract is CheckAndAcceptBase, ValidatorBase, ProxyBase, ConfigParamsBase, ParticipantBase, RoundsBase, IDePool {

    /*
     * Constants
     */

    // Fraction (pct) of participant rewards in totalRewards.
    uint8 constant PART_FRACTION = 70;
    // Fraction (pct) of validator owner rewards in totalRewards.
    uint8 constant VALIDATOR_FRACTION = 25;
    // Minimal required percentage of validator wallet stake in total round stake.
    uint8 constant VALIDATOR_WALLET_MIN_STAKE = 20;

    // Fee for 'addOrdinaryStake' call
    uint64 constant ADD_STAKE_FEE = 50 milliton;
    // Fee for 'addVesting/addLockStake' call
    uint64 constant ADD_VESTING_OR_LOCK_FEE = 80 milliton;
    // Fee for 'removeOrdinaryStake' call
    uint64 constant REMOVE_ORDINARY_STAKE_FEE = 50 milliton;
    // Fee for 'withdrawPartAfterCompleting' call
    uint64 constant WITHDRAW_PART_AFTER_COMPLETING_FEE = 25 milliton;
    // Fee for 'withdrawAllAfterCompleting' call
    uint64 constant WITHDRAW_ALL_AFTER_COMPLETING_FEE = 30 milliton;
    // Fee for 'transferStake' call
    uint64 constant TRANSFER_STAKE_FEE = 135 milliton;
    // Fee for returning/reinvesting participant's stake when rounds are completed.
    uint64 constant RET_OR_REINV_FEE = 50 milliton;
    // Nanotons attached to answer message to allow a receiver contract
    // to be executed.
    uint64 constant ANSWER_MSG_FEE = 3 milliton;

    // Number of participant's stakes reinvesting in 1 transaction.
    uint8 constant MAX_MSGS_PER_TR = 25;
    // Max count of output actions
    uint16 constant MAX_QTY_OF_OUT_ACTIONS = 250; // Real value is equal 255
    // Max count of participant that can be handled at once in function completeRound
    uint32 MAX_PARTICIPANTS = uint32(MAX_QTY_OF_OUT_ACTIONS) * MAX_MSGS_PER_TR;
    // Value attached to message for self call
    uint64 constant VALUE_FOR_SELF_CALL = 1 ton;


    /*
     * Global variables
     */

    // Indicates that pool is closed. Closed pool doesn't accept stakes from other contracts.
    bool m_poolClosed;

    // Min stake accepted to the pool in nTon (for gas efficiency reasons): 10 tons is recommended.
    uint64 m_minStake;

    // Minimum round total stake
    uint64 m_minRoundStake;

    // DePool annual interest, this value is recalculated after each round with reward.
    uint64 m_lastRoundInterest;

    /*
     * Events
     */

    // Event emitted in terminator() function
    event dePoolPoolClosed();

    // This events are emitted on accepting/rejecting stake by elector.
    event roundStakeIsAccepted(uint64 queryId, uint32 comment);
    event roundStakeIsRejected(uint64 queryId, uint32 comment);

    // This is emitted if stake is returned by proxy (IProxy.process_new_stake)
    event proxyHasRejectedTheStake(uint64 queryId);
    // This event are emitted if stake is returned by proxy (IProxy.process_new_stake)
    event proxyHasRejectedRecoverRequest(uint64 roundId);

    // Event emitted in startRoundCompleting() function
    event RoundCompleted(TruncatedRound round);

    // Event emitted when round is switched from pooling to election
    event stakeSigningRequested(uint32 electionId, address proxy);

    /// @dev Constructor with the elector address, the 1st validator in validator pool, the owner and elections parameters.
    constructor(
        uint64 minRoundStake,
        address proxy0,
        address proxy1,
        address validatorWallet,
        uint64 minStake
    )
        CheckAndAcceptBase(minStake, minRoundStake)
        ValidatorBase(validatorWallet)
        ProxyBase(proxy0, proxy1)
        public
    {
        m_minRoundStake = minRoundStake;
        m_minStake = minStake;
        m_poolClosed = false;

        (, uint32 electionsStartBefore, ,) = roundTimeParams();
        (uint256 curValidatorHash, , uint32 validationEnd) = getCurValidatorData();
        uint256 prevValidatorHash = getPrevValidatorHash();
        bool areElectionsStarted = now >= validationEnd - electionsStartBefore;

        Round r2 = generateRound();
        Round r1 = generateRound();
        Round r0 = generateRound();
        (r2.step, r2.completionReason, r2.unfreeze) = (RoundStep.Completed, CompletionReason.FakeRound, 0);
        (r1.step, r1.completionReason, r1.unfreeze) = (RoundStep.WaitingUnfreeze, CompletionReason.FakeRound, 0);
        r1.vsetHashInElectionPhase = areElectionsStarted? curValidatorHash : prevValidatorHash;
        m_rounds[r0.id] = r0;
        m_rounds[r1.id] = r1;
        m_rounds[r2.id] = r2;
    }

    /*
     * modifiers
     */

    modifier onlyInternalMessage {
        // allow call only from other contracts.
        require(msg.sender != address(0), Errors.IS_EXT_MSG);
        _;
    }

    modifier selfCall {
        require(msg.sender == address(this), Errors.IS_NOT_DEPOOL);
        _;
    }

    /* ---------- Miscellaneous private function ---------- */

    /// @notice Helper function to return unused tons back to caller contract.
    function _returnChange() private pure {
        msg.sender.transfer(0, false, 64);
    }

    /// @dev helper function for calculation round interest.
    /// Returns last calculated value. If no rewards in round, returns 0.
    function _calcLastRoundInterest(uint64 totalStake, uint64 rewards) private pure inline returns (uint64) {
        return totalStake != 0 ? math.muldiv(rewards, 100 * 1e9, totalStake) : 0;
    }

    /// @dev Generates a message with error code and parameter sent back to caller contract.
    /// @param errcode Error code.
    /// @param comment Additional parameter according to error code.
    function _sendError(uint32 errcode, uint64 comment) private {
        IParticipant(msg.sender).receiveAnswer{value:0, bounce: false, flag: 64}(errcode, comment);
    }

    /// @dev Send a message with success status to participant meaning that operation is completed successfully.
    /// @param fee Operation fee value that was consumed for operation.
    function _sendAccept(uint64 fee) private {
        IParticipant(msg.sender).receiveAnswer{value: ANSWER_MSG_FEE, bounce: false}(STATUS_SUCCESS, fee);
    }

    /*
     *  Round functions
     */

    function startRoundCompleting(Round round, CompletionReason reason) private returns (Round) {
        round.completionReason = reason;
        round.step = RoundStep.Completing;

        round.end = uint32(now);
        this.completeRound{flag: 1, bounce: false, value: VALUE_FOR_SELF_CALL}(round.id, round.participantQty);

        emit RoundCompleted(toTruncatedRound(round));

        return round;
    }

    function cutWithdrawalValueAndActivateStake(InvestParams p) private view returns (optional(InvestParams), uint64) {
        uint64 periodQty = (uint64(now) - p.lastWithdrawalTime) / p.withdrawalPeriod;
        uint64 withdrawal = math.min(periodQty * p.withdrawalValue, p.amount);
        p.amount -= withdrawal;
        if (p.amount < m_minStake) {
            withdrawal += p.amount;
            p.amount = 0;
        }
        p.lastWithdrawalTime += periodQty * p.withdrawalPeriod;
        p.isActive = true;
        optional(InvestParams) opt;
        opt.set(p);
        return (opt, withdrawal);
    }

    /// @param completedRound Completing round by some any reason (elector return reward, loose elections, etc.)
    /// @param round0 Round that is in pooling state
    /// @param addr Participant address from completed round
    /// @param stakes Participant stake in completed round
    function _returnOrReinvestForParticipant(
        Round completedRound,
        Round round0,
        address addr,
        StakeValue stakes
    ) private inline returns (Round) {
        bool validatorIsPunished = completedRound.completionReason == CompletionReason.ValidatorIsPunished;
        optional(DePoolLib.Participant) optParticipant = m_participants.fetch(addr);
        require(optParticipant.hasValue(), InternalErrors.ERROR511);
        DePoolLib.Participant participant = optParticipant.get();
        --participant.roundQty;
        bool isZeroRoundStake = completedRound.stake == 0;

        // upd ordinary stake
        uint64 newStake;
        uint64 reward;
        if (validatorIsPunished) {
            newStake = math.muldiv(completedRound.unused, stakes.ordinary, completedRound.stake);
        } else {
            if (!isZeroRoundStake) {
                int stakeSum = activeStakeSum(stakes);
                reward = uint64(math.max(
                    math.muldiv(stakeSum, completedRound.rewards, completedRound.stake) - int(RET_OR_REINV_FEE),
                    0
                ));
            }
            participant.reward += reward;
            newStake = stakes.ordinary + reward;
        }

        // upd vesting
        optional(InvestParams) newVesting = stakes.vesting;
        if (newVesting.hasValue()) {
            if (validatorIsPunished && newVesting.get().isActive) {
                InvestParams params = newVesting.get();
                params.amount = math.muldiv(completedRound.unused, params.amount, completedRound.stake);
                newVesting.set(params);
            }
            uint64 withdrawalVesting;
            (newVesting, withdrawalVesting) = cutWithdrawalValueAndActivateStake(newVesting.get());
            newStake += withdrawalVesting;
        }

        // pause stake and newStake
        uint64 attachedValue;
        uint64 curPause = math.min(participant.withdrawValue, newStake);
        attachedValue += curPause;
        participant.withdrawValue -= curPause;
        newStake -= curPause;
        if (newStake < m_minStake) { // whole stake is transferred to unused
            attachedValue += newStake;
            newStake = 0;
        }

        // upd lock
        optional(InvestParams) newLock = stakes.lock;
        if (newLock.hasValue()) {
            if (validatorIsPunished && newLock.get().isActive) {
                InvestParams params = newLock.get();
                params.amount = math.muldiv(completedRound.unused, params.amount, completedRound.stake);
                newLock.set(params);
            }
            uint64 withdrawalLock;
            (newLock, withdrawalLock) = cutWithdrawalValueAndActivateStake(newLock.get());
            if (withdrawalLock != 0) {
                newLock.get().owner.transfer(withdrawalLock, false, 1);
            }
        }

        if (m_poolClosed) {
            attachedValue += newStake;
            if (newVesting.hasValue()) {
                newVesting.get().owner.transfer(newVesting.get().amount, false, 1);
            }
            if (newLock.hasValue()) {
                newLock.get().owner.transfer(newLock.get().amount, false, 1);
            }
        } else {
            if (newVesting.hasValue() && newVesting.get().amount == 0) newVesting.reset();
            if (newLock.hasValue() && newLock.get().amount == 0) newLock.reset();

            attachedValue += 1;
            if (!participant.reinvest) {
                attachedValue += newStake;
                newStake = 0;
            }
            (round0, participant) = _addStakes(round0, participant, addr, newStake, newVesting, newLock);
        }

        _setOrDeleteParticipant(addr, participant);
        IParticipant(addr).onRoundComplete{value: attachedValue, bounce: false}(
            completedRound.id,
            reward,
            stakes.ordinary,
            stakes.vesting.hasValue() && stakes.vesting.get().isActive? stakes.vesting.get().amount : 0,
            stakes.lock.hasValue() && stakes.lock.get().isActive? stakes.lock.get().amount : 0,
            participant.reinvest,
            uint8(completedRound.completionReason)
        );

        return round0;
    }

    /// @dev Internal routine for reinvesting stakes of completed round to last round.
    /// Iterates over stakes of completed round no more then MAX_MSGS_PER_TR times.
    /// Sets round step to STEP_COMPLETING if there are more stakes then MAX_MSGS_PER_TR.
    /// Otherwise sets step to STEP_COMPLETED.
    /// @param round Round structure that should be completed.
    function _returnOrReinvest(Round round, uint8 chunkSize) private returns (Round) {
        tvm.accept();
        Round round0 = m_rounds.fetch(m_roundQty - 1).get();
        mapping(address => StakeValue) stakes = round.stakes;
        uint sentMsgs = 0;
        while (!stakes.empty() && sentMsgs < chunkSize) {
            sentMsgs++;
            (address addr, StakeValue stake) = stakes.delMin();
            round0 = _returnOrReinvestForParticipant(round, round0, addr, stake);
        }
        m_rounds[m_roundQty - 1] = round0;
        round.stakes = stakes;
        if (stakes.empty()) {
            round.step = RoundStep.Completed;
            this.ticktock{value: VALUE_FOR_SELF_CALL, bounce: false}();
        }
        return round;
    }

    /*
     * Public Functions
     */

    function calculateStakeWithAssert(bool doSplit, uint64 wholeFee) private returns (uint64 /*stake*/, bool /*ok*/) {
        uint64 div = doSplit ? 2 : 1;
        uint64 stake = uint64(msg.value / div);
        uint64 fee = wholeFee / div;

        // send stake back if stake is less then minimal
        if (stake < m_minStake + fee) {
            _sendError(STATUS_STAKE_TOO_SMALL, m_minStake * div + wholeFee);
            return (0, false);
        }
        // or if pool is closed
        if (m_poolClosed) {
            _sendError(STATUS_DEPOOL_CLOSED, 0);
            return (0, false);
        }

        return (stake - fee, true);
    }

    /// @dev A method to add a participant or add stake by an existing participant in the last active round.
    function addOrdinaryStake(bool reinvest) public onlyInternalMessage {
        DePoolLib.Participant participant = m_participants[msg.sender];

        (uint64 stake, bool ok) = calculateStakeWithAssert(false, ADD_STAKE_FEE);
        if (!ok) {
            return ;
        }

        Round round = m_rounds.fetch(m_roundQty - 1).get();

        optional(InvestParams) empty;
        (round, participant) = _addStakes(round, participant, msg.sender, stake, empty, empty);
        m_rounds[m_roundQty - 1] = round;

        participant.reinvest = reinvest;
        _setOrDeleteParticipant(msg.sender, participant);

        _sendAccept(ADD_STAKE_FEE);
    }

    /// @dev Function remove 'withdrawValue' from participant's ordinary stake only from pooling round.
    /// If ordinary stake become less than minStake than whole stake is send to participant.
    function removeOrdinaryStake(uint64 withdrawValue) public onlyInternalMessage {
        if (msg.value < REMOVE_ORDINARY_STAKE_FEE) {
            return _sendError(STATUS_MSG_VAL_TOO_SMALL, REMOVE_ORDINARY_STAKE_FEE);
        }

        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(DePoolLib.Participant) optParticipant = m_participants.fetch(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        DePoolLib.Participant participant = optParticipant.get();

        uint64 removedPoolingStake;
        (removedPoolingStake, participant) = withdrawStakeInPoolingRound(participant, msg.sender, withdrawValue, m_minStake);
        _setOrDeleteParticipant(msg.sender, participant);
        msg.sender.transfer(removedPoolingStake, false, 1);
    }

    /// @dev A method to add the vesting for participant in the last active round.
    /// @param beneficiary Contract address for vesting
    /// @param totalPeriod Total period of vesting in seconds
    /// @param withdrawalPeriod The period in seconds after which you can withdraw money
    function addVestingStake(address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod) public {
        addVestingOrLock(beneficiary, withdrawalPeriod, totalPeriod, true);
    }

    function addLockStake(address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod) public {
        addVestingOrLock(beneficiary, withdrawalPeriod, totalPeriod, false);
    }

    function addVestingOrLock(address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod, bool isVesting) private {
        require(beneficiary.isStdAddrWithoutAnyCast(), Errors.INVALID_ADDRESS);
        if (beneficiary == address(0)) {
            beneficiary = msg.sender;
        }

        (uint64 halfStake, bool ok) = calculateStakeWithAssert(true, ADD_VESTING_OR_LOCK_FEE);
        if (!ok) {
            return ;
        }

        if (withdrawalPeriod > totalPeriod) {
            return _sendError(STATUS_WITHDRAWAL_PERIOD_GREATER_TOTAL_PERIOD, 0);
        }

        if (totalPeriod >= 18 * (365 days)) { // ~18 years
            return _sendError(STATUS_TOTAL_PERIOD_MORE_18YEARS, 0);
        }

        if (withdrawalPeriod == 0) {
            return _sendError(STATUS_WITHDRAWAL_PERIOD_IS_ZERO, 0);
        }

        if (totalPeriod % withdrawalPeriod != 0) {
            return _sendError(STATUS_TOTAL_PERIOD_IS_NOT_DIVED_BY_WITHDRAWAL_PERIOD, 0);
        }

        DePoolLib.Participant participant = m_participants[beneficiary];
        if (isVesting) {
            if (participant.haveVesting) {
                return _sendError(STATUS_PARTICIPANT_HAVE_ALREADY_VESTING, 0);
            }
        } else {
            if (participant.haveLock) {
                return _sendError(STATUS_PARTICIPANT_HAVE_ALREADY_LOCK, 0);
            }
        }

        uint64 withdrawalValue = math.muldiv(halfStake, withdrawalPeriod, totalPeriod);
        if (withdrawalValue == 0) {
            return _sendError(STATUS_PERIOD_PAYMENT_IS_ZERO, 0);
        }

        InvestParams vestingOrLock = InvestParams({
            isActive: false,
            amount: halfStake,
            lastWithdrawalTime: uint64(now),
            withdrawalPeriod: withdrawalPeriod,
            withdrawalValue: withdrawalValue,
            owner: msg.sender
        });

        for (uint64 i = 1; i <= 2; ++i) {
            uint64 round_id = m_roundQty - i;
            Round round = m_rounds.fetch(round_id).get();
            vestingOrLock.isActive = round.step == RoundStep.WaitingValidatorRequest || i == 1;
            optional(InvestParams) v;
            optional(InvestParams) l;
            if (isVesting) {
                v.set(vestingOrLock);
            } else {
                l.set(vestingOrLock);
            }
            (round, participant) = _addStakes(round, participant, beneficiary, 0, v, l);
            m_rounds[round_id] = round;
        }

        _setOrDeleteParticipant(beneficiary, participant);
        _sendAccept(ADD_STAKE_FEE);
    }

    /// @dev Allows a participant to withdraw some value from depool. This function withdraw 'withdrawValue' nanotons
    /// when rounds are completed while not transfer 'withdrawValue' nanotons to participant.
    /// If participant stake is became less 'minStake' than the whole stake are sent to participant.
    function withdrawPartAfterCompleting(uint64 withdrawValue) public onlyInternalMessage {
        if (msg.value < WITHDRAW_PART_AFTER_COMPLETING_FEE) {
            return _sendError(STATUS_MSG_VAL_TOO_SMALL, WITHDRAW_PART_AFTER_COMPLETING_FEE);
        }

        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(DePoolLib.Participant) optParticipant = m_participants.fetch(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        DePoolLib.Participant participant = optParticipant.get();

        participant.withdrawValue = withdrawValue;
        _setOrDeleteParticipant(msg.sender, participant);
        _sendAccept(WITHDRAW_PART_AFTER_COMPLETING_FEE);
    }


    /// @dev if removeAll is true that whole ordinary stakes with rewards will be send to participant when rounds are completed
    function withdrawAllAfterCompleting(bool doWithdrawAll) public onlyInternalMessage {
        if (msg.value < WITHDRAW_ALL_AFTER_COMPLETING_FEE) {
            return _sendError(STATUS_MSG_VAL_TOO_SMALL, WITHDRAW_ALL_AFTER_COMPLETING_FEE);
        }
        optional(DePoolLib.Participant) optParticipant = m_participants.fetch(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        DePoolLib.Participant participant = optParticipant.get();
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        participant.reinvest = !doWithdrawAll;
        _setOrDeleteParticipant(msg.sender, participant);
        _sendAccept(WITHDRAW_ALL_AFTER_COMPLETING_FEE);
    }

    /// @dev Transfer stake or part of it to another participant
    /// @param dest New owner of stake
    /// @param amount value transfer to dest in nanotons
    /// Use amount=0 to transfer the all stakes
    function transferStake(address dest, uint64 amount) public onlyInternalMessage {
        // target address should be set.
        require(dest.isStdAddrWithoutAnyCast() && !dest.isStdZero(), Errors.INVALID_ADDRESS);

        // check self transfer
        address src = msg.sender;
        if (src == dest)  {
            return _sendError(STATUS_TRANSFER_SELF, 0);
        }

        optional(DePoolLib.Participant) optSrcParticipant = m_participants.fetch(src);
        if (!optSrcParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        DePoolLib.Participant srcParticipant = optSrcParticipant.get();

        // return error if msg value doesn't cover the fee
        if (msg.value < TRANSFER_STAKE_FEE) {
            return _sendError(STATUS_MSG_VAL_TOO_SMALL, TRANSFER_STAKE_FEE);
        }

        // return error if pool is closed
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        if (amount == 0) {
            amount = DePoolLib.MAX_UINT64;
        }

        DePoolLib.Participant destParticipant = m_participants[dest];

        uint64 totalSrcStake;
        uint64 transferred;
        mapping(uint64 => Round) rounds = m_rounds;
        optional(uint64, Round) pair = rounds.min();
        while (pair.hasValue() && transferred < amount) {
            (uint64 roundId, Round round) = pair.get();
            uint64 currentTransferred;
            uint64 srcStake;
            (rounds[roundId], currentTransferred, srcStake, srcParticipant, destParticipant)
                = transferStakeInOneRound(
                    round,
                    srcParticipant,
                    destParticipant,
                    src,
                    dest,
                    amount - transferred,
                    m_minStake
                );
            transferred += currentTransferred;
            totalSrcStake += srcStake;
            pair = rounds.next(roundId);
        }

        if (amount != DePoolLib.MAX_UINT64) {
            if (totalSrcStake < amount) {
                return _sendError(STATUS_TRANSFER_AMOUNT_IS_TOO_BIG, 0);
            }

            if (transferred < amount) {
                return _sendError(STATUS_REMAINING_STAKE_LESS_THAN_MINIMAL, 0);
            }
        }

        m_rounds = rounds;

        _setOrDeleteParticipant(src, srcParticipant);
        _setOrDeleteParticipant(dest, destParticipant);

        IParticipant(dest).onTransfer{bounce: false}(src, amount);
        _sendAccept(TRANSFER_STAKE_FEE);
    }

    // This function have function id same as function `process_new_stake` in elector contract. Because validator
    // can send request to DePool or to election contract using same interface.
    function participateInElections(
        uint64 queryId,
        uint256 validatorKey,
        uint32 stakeAt,
        uint32 maxFactor,
        uint256 adnlAddr,
        bytes signature
    ) public functionID(0x4E73744B) onlyValidatorContract {
        require(!m_poolClosed, Errors.DEPOOL_IS_CLOSED);
        tvm.accept();
        Round round = m_rounds.fetch(m_roundQty - 2).get();
        require(round.step == RoundStep.WaitingValidatorRequest, Errors.NO_ELECTION_ROUND);
        require(stakeAt == round.supposedElectedAt, Errors.INVALID_ELECTION_ID);

        round.validatorRequest = DePoolLib.Request(queryId, validatorKey, stakeAt, maxFactor, adnlAddr, signature);
        _sendElectionRequest(round.proxy, round.id, round.stake, round.validatorRequest, round.elector);
        round.step = RoundStep.WaitingIfStakeAccepted;
        m_rounds[m_roundQty - 2] = round;

        _returnChange();
    }

    function generateRound() internal returns (Round) {
        DePoolLib.Request req;
        Round r = Round({
            id: m_roundQty,
            supposedElectedAt: 0, // set when round in elections phase
            unfreeze: DePoolLib.MAX_TIME, // set when round in unfreeze phase
            step: RoundStep.Pooling,
            completionReason: CompletionReason.Undefined,
            participantQty : 0,
            stake: 0,
            rewards: 0,
            unused: 0,
            validatorRequest: req,
            proxy: getProxy(m_roundQty),
            start: uint32(now),
            end: 0, // set when round is switch to Completing step
            elector: address(0), // set when round in elections phase
            vsetHashInElectionPhase: 0 // set when round in elections phase
        });
        ++m_roundQty;
        return r;
    }

    function updateRound2(
            Round round2,
            uint256 prevValidatorHash,
            uint256 curValidatorHash,
            uint32 validationStart,
            uint32 stakeHeldFor
        )
        private returns (Round)
    {
        if (round2.step == RoundStep.Completing) {
            this.completeRoundWithChunk{bounce: false}(round2.id, 1);
            // For situations when exist stake with value==V, but DePool balance == (V - epsilon)
            // In such situations some extra funds must be sent to DePool balance (See function 'receiveFunds')
        }

        if (round2.step == RoundStep.WaitingValidatorRequest) {
            round2.step = RoundStep.WaitingUnfreeze;
            // it's true if stake has been send to elector and has been rejected by elector
            if (round2.completionReason == CompletionReason.Undefined) {
                round2.completionReason = CompletionReason.NoValidatorRequest;
            }
            round2.unfreeze = 0;
        }

        // try to update unfreeze time
        if (round2.vsetHashInElectionPhase != curValidatorHash &&
            round2.vsetHashInElectionPhase != prevValidatorHash &&
            round2.unfreeze == DePoolLib.MAX_TIME) {
            // at least 1 validation period is skipped
            round2.unfreeze = validationStart + stakeHeldFor;
        }

        // try to complete round
        if (now >= uint(round2.unfreeze) + DePoolLib.ELECTOR_UNFREEZE_LAG) {
            if (round2.step == RoundStep.WaitingUnfreeze &&
                round2.completionReason != CompletionReason.Undefined) {
                if (round2.participantQty == 0) {
                    round2.step = RoundStep.Completed;
                    round2.end = uint32(now); // just for logging
                    emit RoundCompleted(toTruncatedRound(round2));
                } else {
                    // just complete round
                    round2 = startRoundCompleting(round2, round2.completionReason);
                }
            } else if (round2.step < RoundStep.WaitingReward) {
                // recover stake and complete round
                round2.step = RoundStep.WaitingReward;
                _recoverStake(round2.proxy, round2.id, round2.elector);
            }
        }
        return round2;
    }

    function updateRounds() private {
        (/*uint32 validatorsElectedFor*/, uint32 electionsStartBefore, /*uint32 electionsEndBefore*/, uint32 stakeHeldFor)
            = roundTimeParams();
        (uint256 curValidatorHash, uint32 validationStart, uint32 validationEnd) = getCurValidatorData();
        uint256 prevValidatorHash = getPrevValidatorHash();
        bool areElectionsStarted = now >= validationEnd - electionsStartBefore;
        Round round0 = m_rounds.fetch(m_roundQty - 1).get(); // round is in pooling phase
        Round round1 = m_rounds.fetch(m_roundQty - 2).get(); // round is in election or validation phase
        Round round2 = m_rounds.fetch(m_roundQty - 3).get(); // round is in validation or investigation round

        round2 = updateRound2(round2, prevValidatorHash, curValidatorHash, validationStart, stakeHeldFor);

        // try to switch rounds
        if (areElectionsStarted && // elections are started
            round1.vsetHashInElectionPhase != curValidatorHash && // and pooling round is not switch to election phase yet
            round2.step == RoundStep.Completed // and round2 completed (stakes are reinvested to pooling round)
        ) {
            // we need to rotate rounds
            delete m_rounds[round2.id];
            round2 = round1;
            round1 = round0;
            round0 = generateRound();

            round2 = updateRound2(round2, prevValidatorHash, curValidatorHash, validationStart, stakeHeldFor);

            round1.supposedElectedAt = validationEnd;
            round1.elector = getElector();
            round1.vsetHashInElectionPhase = curValidatorHash;
            // check that round total stake is greater or equal to minimum stake
            bool isTotalStakeOk = round1.stake >= m_minRoundStake;
            // and validator wallet made a necessary minimal stake in round
            bool isValidatorStake  = activeStakeSum(round1.stakes[m_validatorWallet]) >=
                                math.muldiv(m_minRoundStake, VALIDATOR_WALLET_MIN_STAKE, 100);
            if (!isTotalStakeOk || !isValidatorStake) {
                round1.step = RoundStep.WaitingUnfreeze;
                round1.completionReason = isTotalStakeOk ?
                                            CompletionReason.ValidatorStakeIsTooSmall :
                                            CompletionReason.TotalStakeIsTooSmall;
                round1.unfreeze = 0;
            } else {
                round1.step = RoundStep.WaitingValidatorRequest;
                emit stakeSigningRequested(round1.supposedElectedAt, round1.proxy);
            }
        }

        // New validator set is set. Let's recover stake to know if we win the elections
        if (round1.step == RoundStep.WaitingValidationStart &&
            round1.vsetHashInElectionPhase == prevValidatorHash
        )
        {
            round1.step = RoundStep.WaitingIfValidatorWinElections;
            _recoverStake(round1.proxy, round1.id, round1.elector);
        }

        m_rounds[m_roundQty - 1] = round0;
        m_rounds[m_roundQty - 2] = round1;
        m_rounds[m_roundQty - 3] = round2;
    }

    /// @dev Updates round states, sends election requests and accepts rewards.
    function ticktock() public override onlyInternalMessage {
        updateRounds();
        _returnChange();
    }

    /// @dev Allows to return or reinvest part of stakes from last completed round.
    /// Function can be called only by staking itself.
    function completeRoundWithChunk(uint64 roundId, uint8 chunkSize) public selfCall {
        tvm.accept();
        require(roundId == m_roundQty - 3 || roundId != m_roundQty - 3 && m_poolClosed, InternalErrors.ERROR522);
        optional(Round) optRound = m_rounds.fetch(roundId);
        require(optRound.hasValue(), InternalErrors.ERROR519);
        Round round = optRound.get();
        require(round.step == RoundStep.Completing, InternalErrors.ERROR518);

        round = _returnOrReinvest(round, chunkSize);

        if (chunkSize < MAX_MSGS_PER_TR && !round.stakes.empty()) {
            uint8 doubleChunkSize = 2 * chunkSize;
            this.completeRoundWithChunk{flag: 1, bounce: false}(
                roundId,
                doubleChunkSize < MAX_MSGS_PER_TR? doubleChunkSize : chunkSize
            );
            this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, chunkSize);
        }

        m_rounds[roundId] = round;
    }

    function completeRound(uint64 roundId, uint32 participantQty) public selfCall {
        tvm.accept();
        require(roundId == m_roundQty - 3 || roundId != m_roundQty - 3 && m_poolClosed, InternalErrors.ERROR522);
        optional(Round) optRound = m_rounds.fetch(roundId);
        require(optRound.hasValue(), InternalErrors.ERROR519);
        Round round = optRound.get();
        require(round.step == RoundStep.Completing, InternalErrors.ERROR518);

        this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, 1);
        tvm.commit();
        tvm.accept();
        if (participantQty < MAX_MSGS_PER_TR) {
            round = _returnOrReinvest(round, MAX_MSGS_PER_TR);
            m_rounds[roundId] = round;
        } else {
            uint outActionQty = (participantQty + MAX_MSGS_PER_TR - 1) / MAX_MSGS_PER_TR; // Count of message in "else" branch. See below
            if (outActionQty > MAX_QTY_OF_OUT_ACTIONS) {
                uint32 restParticipant = participantQty;
                for (int msgQty = 0; restParticipant > 0; ++msgQty) {
                    uint32 curGroup =
                        (restParticipant < MAX_PARTICIPANTS || msgQty + 1 == MAX_QTY_OF_OUT_ACTIONS)?
                        restParticipant :
                        MAX_PARTICIPANTS;
                    this.completeRound{flag: 1, bounce: false}(roundId, curGroup);
                    restParticipant -= curGroup;
                }
            } else {
                for (uint i = 0; i < participantQty; i += MAX_MSGS_PER_TR) {
                    this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, MAX_MSGS_PER_TR);
                }
            }
        }
    }


    /*
     * -------------- Public functions called by proxy contract only --------------------------
     */

    // Called by Elector in process_new_stake function if our stake is accepted in elections
    function onStakeAccept(uint64 queryId, uint32 comment, address elector) public override {
        optional(Round) optRound = m_rounds.fetch(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        require(round.id == queryId, Errors.INVALID_QUERY_ID);
        require(round.step == RoundStep.WaitingIfStakeAccepted, Errors.INVALID_ROUND_STEP);

        tvm.accept();
        round.step = RoundStep.WaitingValidationStart;
        round.completionReason = CompletionReason.Undefined;
        m_rounds[queryId] = round;

        emit roundStakeIsAccepted(round.validatorRequest.queryId, comment);
    }

    // Called by Elector in process_new_stake function if error occurred.
    function onStakeReject(uint64 queryId, uint32 comment, address elector) public override {
        // The return value is for logging, to catch outbound external message
        // and print queryId and comment.
        optional(Round) optRound = m_rounds.fetch(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        require(round.id == queryId, Errors.INVALID_QUERY_ID);
        require(round.step == RoundStep.WaitingIfStakeAccepted, Errors.INVALID_ROUND_STEP);

        round.step = RoundStep.WaitingValidatorRequest;
        round.completionReason = CompletionReason.StakeIsRejectedByElector;
        m_rounds[queryId] = round;

        emit roundStakeIsRejected(round.validatorRequest.queryId, comment);
    }

    function acceptRewardAndStartRoundCompleting(Round round, uint64 value) private returns (Round){
        uint64 effectiveStake = round.stake - round.unused;
        uint64 totalReward = value - effectiveStake;
        round.rewards = math.muldiv(totalReward, PART_FRACTION, 100);
        uint64 validatorReward = math.muldiv(totalReward, VALIDATOR_FRACTION, 100);
        m_validatorWallet.transfer(validatorReward, false, 1);
        m_lastRoundInterest = _calcLastRoundInterest(effectiveStake, round.rewards);
        round = startRoundCompleting(round, CompletionReason.RewardIsReceived);
        return round;
    }

    // Called by Elector contract as answer to recover_stake request.
    function onSuccessToRecoverStake(uint64 queryId, address elector) public override {
        optional(Round) optRound = m_rounds.fetch(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        uint64 value = uint64(msg.value) + DePoolLib.PROXY_FEE;
        if (round.step == RoundStep.WaitingIfValidatorWinElections) {
            if (value < round.stake) {
                // only part of round stake is returned - we won the election,
                // but round stake is cut-off by elector,
                // optimize a minimum round stake
                round.step = RoundStep.WaitingUnfreeze;
                round.unused = value;
                m_minRoundStake = round.stake - round.unused;
            } else {
                // value +/- epsilon == round.stake, so elections are lost
                round.step = RoundStep.WaitingUnfreeze;
                round.completionReason = CompletionReason.ElectionsAreLost;
                m_minRoundStake += m_minRoundStake / 4;
            }
        } else if (round.step == RoundStep.WaitingReward) {
            if (value >= round.stake - round.unused) {
                round = acceptRewardAndStartRoundCompleting(round, value);
            } else {
                round = startRoundCompleting(round, CompletionReason.ValidatorIsPunished);
                round.unused += value;
            }
        } else {
            revert(InternalErrors.ERROR521);
        }

        m_rounds[queryId] = round;
    }

    function onFailToRecoverStake(uint64 queryId, address elector) public override {
        optional(Round) optRound = m_rounds.fetch(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        if (round.step == RoundStep.WaitingIfValidatorWinElections) {
            // DePool win elections and our stake is locked by elector.
             round.step = RoundStep.WaitingUnfreeze;
        } else if (round.step == RoundStep.WaitingReward) {
            // Validator is banned! Cry.
            round = startRoundCompleting(round, CompletionReason.ValidatorIsPunished);
        } else {
            revert(InternalErrors.ERROR521);
        }
        m_rounds[queryId] = round;
    }

    /*
     * ----------- Owner functions ---------------------
     */

    /// @dev Allows to close pool or complete pending round.
    /// Closed pool restricts deposit stakes. Stakes in last round are sent to
    /// participant's wallets immediately. Stakes in other rounds will be returned
    /// when rounds will be completed.
    function terminator() public onlyOwner {
        require(!m_poolClosed, Errors.DEPOOL_IS_CLOSED);
        m_poolClosed = true;
        tvm.commit();
        tvm.accept();
        Round round0 = m_rounds.fetch(m_roundQty - 1).get();
        Round round1 = m_rounds.fetch(m_roundQty - 2).get();
        round0 = startRoundCompleting(round0, CompletionReason.PoolClosed);
        if (round1.step == RoundStep.WaitingValidatorRequest) {
            round1 = startRoundCompleting(round1, CompletionReason.PoolClosed);
        }
        emit dePoolPoolClosed();
        m_rounds[m_roundQty - 1] = round0;
        m_rounds[m_roundQty - 2] = round1;
    }

    /*
     * Fallback function.
     */

    // function that receive funds
    function receiveFunds() public pure {
    }

    receive() external {
        _returnChange();
    }

    fallback() external {}

    onBounce(TvmSlice body) external {
        uint32 functionId = body.decode(uint32);
        bool isProcessNewStake = functionId == tvm.functionId(IProxy.process_new_stake);
        bool isRecoverStake = functionId == tvm.functionId(IProxy.recover_stake);
        if (isProcessNewStake || isRecoverStake) {
            uint64 roundId = body.decode(uint64);
            optional(Round) optRound = m_rounds.fetch(roundId);
            if (isProcessNewStake) {
                require(roundId == m_roundQty - 2, InternalErrors.ERROR524);
                Round r1 = optRound.get();
                require(r1.step == RoundStep.WaitingIfStakeAccepted, InternalErrors.ERROR525);
                r1.step = RoundStep.WaitingValidatorRequest; // roll back step
                emit proxyHasRejectedTheStake(r1.validatorRequest.queryId);
                optRound.set(r1);
            } else {
                if (roundId == m_roundQty - 3) {
                    Round r2 = optRound.get();
                    require(r2.step == RoundStep.WaitingReward, InternalErrors.ERROR526);
                    r2.step = RoundStep.WaitingUnfreeze; // roll back step
                    optRound.set(r2);
                } else if (roundId == m_roundQty - 2) {
                    Round r1 = optRound.get();
                    require(r1.step == RoundStep.WaitingIfValidatorWinElections, InternalErrors.ERROR527);
                    r1.step = RoundStep.WaitingValidationStart; // roll back step
                    optRound.set(r1);
                } else {
                    revert(InternalErrors.ERROR528);
                }
                emit proxyHasRejectedRecoverRequest(roundId);
            }
            m_rounds[roundId] = optRound.get();
        }
    }
}

contract DePool is DePoolContract {

    /// @dev Constructor with the elector address, the 1st validator in validator pool, the owner and elections parameters.
    constructor(
        uint64 minRoundStake,
        address proxy0,
        address proxy1,
        address validatorWallet,
        uint64 minStake
    )
        DePoolContract(minRoundStake, proxy0, proxy1, validatorWallet, minStake)
        public
    {
    }

    /*
     * Public Getters
     */

    /// @dev Allows to check participant's information in all rounds.
    function getParticipantInfo(address addr) public view
        returns (
            uint64 total,
            uint64 withdrawValue,
            bool reinvest,
            uint64 reward,
            mapping (uint64 => uint64) stakes,
            mapping (uint64 => InvestParams) vestings,
            mapping (uint64 => InvestParams) locks
        )
    {
        optional(DePoolLib.Participant) optParticipant = m_participants.fetch(addr);
        require(optParticipant.hasValue(), Errors.NO_SUCH_PARTICIPANT);
        DePoolLib.Participant participant = optParticipant.get();

        reinvest = participant.reinvest;
        reward = participant.reward;
        withdrawValue = participant.withdrawValue;

        optional(uint64, Round) pair = m_rounds.min();
        while (pair.hasValue()) {
            (uint64 id, Round round) = pair.get();
            optional(StakeValue) optSv = round.stakes.fetch(addr);
            if (optSv.hasValue()) {
                StakeValue sv = optSv.get();
                if (sv.ordinary != 0) {
                    stakes[round.id] = sv.ordinary;
                    total += sv.ordinary;
                }
                if (sv.vesting.hasValue()) {
                    vestings[round.id] = sv.vesting.get();
                    total += sv.vesting.get().amount;
                }
                if (sv.lock.hasValue()) {
                    locks[round.id] = sv.lock.get();
                    total += sv.lock.get().amount;
                }
            }
            pair = m_rounds.next(id);
        }
    }

    function getDePoolInfo() public view returns (
        uint64 minStake,
        uint64 minRoundStake,
        uint64 minValidatorStake,
        address validatorWallet,
        address[] proxies,
        bool poolClosed,

        uint64 interest,

        uint64 addStakeFee,
        uint64 addVestingOrLockFee,
        uint64 removeOrdinaryStakeFee,
        uint64 withdrawPartAfterCompletingFee,
        uint64 withdrawAllAfterCompletingFee,
        uint64 transferStakeFee,
        uint64 retOrReinvFee,
        uint64 answerMsgFee,
        uint64 proxyFee,

        uint64 participantFraction,
        uint64 validatorFraction,
        uint64 validatorWalletMinStake
    )
    {
        minStake = m_minStake;
        minRoundStake = m_minRoundStake;
        minValidatorStake = (m_minRoundStake * VALIDATOR_WALLET_MIN_STAKE) / 100;
        validatorWallet = m_validatorWallet;
        proxies = m_proxies;
        poolClosed = m_poolClosed;

        interest = m_lastRoundInterest;

        addStakeFee = ADD_STAKE_FEE;
        addVestingOrLockFee = ADD_VESTING_OR_LOCK_FEE;
        removeOrdinaryStakeFee = REMOVE_ORDINARY_STAKE_FEE;
        withdrawPartAfterCompletingFee = WITHDRAW_PART_AFTER_COMPLETING_FEE;
        withdrawAllAfterCompletingFee = WITHDRAW_ALL_AFTER_COMPLETING_FEE;
        transferStakeFee = TRANSFER_STAKE_FEE;
        retOrReinvFee = RET_OR_REINV_FEE;
        answerMsgFee = ANSWER_MSG_FEE;
        proxyFee = DePoolLib.PROXY_FEE;

        participantFraction = PART_FRACTION;
        validatorFraction = VALIDATOR_FRACTION;
        validatorWalletMinStake = VALIDATOR_WALLET_MIN_STAKE;
    }

    function getParticipans() external view returns (address[] participans) {
        mapping(address => bool) used;
        optional(address, DePoolLib.Participant) pair = m_participants.min();
        while (pair.hasValue()) {
            (address p, ) = pair.get();
            if (!used.exists(p)) {
                used[p] = true;
                participans.push(p);
            }
            pair = m_participants.next(p);
        }
    }
}
