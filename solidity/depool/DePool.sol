// 2020 (c) TON Venture Studio Ltd

pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;

import "DePoolBase.sol";
import "IDePoolInfoGetter.sol";
import "DePoolProxy.sol";
import "DePoolRounds.sol";
import "IDePool.sol";
import "IParticipant.sol";

contract DePool is ValidatorBase, ProxyBase, ConfigParamsBase, ParticipantBase, RoundsBase, IDePool {

    // Fee for 'addOrdinaryStake/addVesting/addLockStake' that will be returned
    uint64 constant STAKE_FEE = 0.5 ton;
    // Fee for returning/reinvesting participant's stake when rounds are completed.
    uint64 constant RET_OR_REINV_FEE = 50 milliton;
    // Number of participant's stakes reinvested in 1 transaction.
    uint8 constant MAX_MSGS_PER_TR = 25;
    // Max count of output actions
    uint16 constant MAX_QTY_OF_OUT_ACTIONS = 250; // Real value is equal 255
    // Value attached to message for self call
    uint64 constant VALUE_FOR_SELF_CALL = 1 ton;


    // Hash of code of proxy contract
    uint256 constant PROXY_CODE_HASH = 0x334603dc8cfd56ff3df70032abbe42b9c8a4c5fca7606d74a9d9d772097883af;

    // Status codes for messages sent back to participants as result of
    // operations (add/remove/continue/withdraw stake):
    uint8 constant STATUS_SUCCESS                                        =  0;
    uint8 constant STATUS_STAKE_TOO_SMALL                                =  1;
    uint8 constant STATUS_DEPOOL_CLOSED                                  =  3;
    uint8 constant STATUS_NO_PARTICIPANT                                 =  6;
    uint8 constant STATUS_PARTICIPANT_HAVE_ALREADY_VESTING               =  9;
    uint8 constant STATUS_WITHDRAWAL_PERIOD_GREATER_TOTAL_PERIOD         = 10;
    uint8 constant STATUS_TOTAL_PERIOD_MORE_18YEARS                      = 11;
    uint8 constant STATUS_WITHDRAWAL_PERIOD_IS_ZERO                      = 12;
    uint8 constant STATUS_TOTAL_PERIOD_IS_NOT_DIVED_BY_WITHDRAWAL_PERIOD = 13;
    uint8 constant STATUS_PERIOD_PAYMENT_IS_ZERO                         = 14;
    uint8 constant STATUS_REMAINING_STAKE_LESS_THAN_MINIMAL              = 16;
    uint8 constant STATUS_PARTICIPANT_HAVE_ALREADY_LOCK                  = 17;
    uint8 constant STATUS_TRANSFER_AMOUNT_IS_TOO_BIG                     = 18;
    uint8 constant STATUS_TRANSFER_SELF                                  = 19;
    uint8 constant STATUS_TRANSFER_TO_OR_FROM_VALIDATOR                  = 20;
    uint8 constant STATUS_FEE_TOO_SMALL                                  = 21;
    uint8 constant STATUS_INVALID_ADDRESS                                = 22;
    uint8 constant STATUS_INVALID_BENEFICIARY                            = 23;
    uint8 constant STATUS_NO_ELECTION_ROUND                              = 24;
    uint8 constant STATUS_INVALID_ELECTION_ID                            = 25;


    /*
     * Global variables
     */

    // Indicates that pool is closed. Closed pool doesn't accept stakes from other contracts.
    bool m_poolClosed;
    // Min stake accepted to the pool in nTon (for gas efficiency reasons): 10 tons is recommended.
    uint64 m_minStake;
    // Minimum validator stake in each round
    uint64 m_validatorAssurance;
    // % of participant rewards
    uint8 m_participantRewardFraction;
    // % of validator rewards
    uint8 m_validatorRewardFraction;
    // Value of balance which DePool tries to maintain (by subtracting necessary value from each round reward)
    uint64 m_balanceThreshold;
    // Value of DePool's balance below which ticktock and participateInElections functions don't execute
    uint64 constant CRITICAL_THRESHOLD = 10 ton;

    /*
     * Events
     */

    // Event emitted when pool is closed by terminator() function.
    event DePoolClosed();

    // Events emitted on accepting/rejecting stake by elector.
    event RoundStakeIsAccepted(uint64 queryId, uint32 comment);
    event RoundStakeIsRejected(uint64 queryId, uint32 comment);

    // Event emitted if stake is returned by proxy (IProxy.process_new_stake) because too low balance of proxy contract.
    event ProxyHasRejectedTheStake(uint64 queryId);
    // Event is emitted if stake cannot be returned from elector (IProxy.recover_stake) because too low balance of proxy contract.
    event ProxyHasRejectedRecoverRequest(uint64 roundId);

    // Event is emitted on completing round.
    event RoundCompleted(TruncatedRound round);

    // Event emitted when round is switched from pooling to election.
    // DePool is waiting for signed election request from validator wallet
    event StakeSigningRequested(uint32 electionId, address proxy);

    /// @dev Event emitted when pure DePool balance becomes too low
    /// @param replenishment Minimal value that must be sent to DePool via 'receiveFunds' function.
    event TooLowDePoolBalance(uint replenishment);

    modifier onlyOwner {
        require(msg.pubkey() == tvm.pubkey(), Errors.IS_NOT_OWNER);
        _;
    }

    /// @dev DePool's constructor.
    /// @param minStake Min stake that participant may have in one round.
    /// @param validatorAssurance Min validator stake.
    /// @param proxyCode Code of proxy contract.
    /// @param validatorWallet Address of validator wallet.
    /// @param participantRewardFraction % of reward that distributed among participants.
    /// @param balanceThreshold Value of balance which DePool tries to maintain.
    constructor(
        uint64 minStake,
        uint64 validatorAssurance,
        TvmCell proxyCode,
        address validatorWallet,
        uint8 participantRewardFraction,
        uint64 balanceThreshold
    )
        ValidatorBase(validatorWallet)
        public
    {
        require(address(this).wid == 0, Errors.NOT_WORKCHAIN0);
        require(msg.pubkey() == tvm.pubkey(), Errors.IS_NOT_OWNER);
        require(tvm.pubkey() != 0, Errors.CONSTRUCTOR_NO_PUBKEY);
        require(minStake >= 1 ton, Errors.BAD_STAKES);
        require(minStake <= validatorAssurance, Errors.BAD_STAKES);
        require(tvm.hash(proxyCode) == PROXY_CODE_HASH, Errors.BAD_PROXY_CODE);
        require(validatorWallet.isStdAddrWithoutAnyCast(), Errors.VALIDATOR_IS_NOT_STD);
        require(participantRewardFraction > 0 && participantRewardFraction < 100, Errors.BAD_PART_REWARD);
        uint8 validatorRewardFraction = 100 -  participantRewardFraction;
        require(balanceThreshold >= CRITICAL_THRESHOLD, Errors.BAD_MINIMUM_BALANCE);

        require(address(this).balance >=
                    balanceThreshold +
                    DePoolLib.DEPOOL_CONSTRUCTOR_FEE +
                    2 * (DePoolLib.MIN_PROXY_BALANCE + DePoolLib.PROXY_CONSTRUCTOR_FEE),
                Errors.BAD_MINIMUM_BALANCE);

        tvm.accept();


        for (uint8 i = 0; i < 2; ++i) {
            TvmBuilder b;
            b.store(address(this), i);
            uint256 publicKey = tvm.hash(b.toCell());
            TvmCell data = tvm.buildEmptyData(publicKey);
            TvmCell stateInit = tvm.buildStateInit(proxyCode, data);
            address proxy =
                new DePoolProxyContract{
                    wid: -1,
                    value: DePoolLib.MIN_PROXY_BALANCE + DePoolLib.PROXY_CONSTRUCTOR_FEE,
                    stateInit: stateInit
                }();
            m_proxies.push(proxy);
        }

        m_poolClosed = false;
        m_minStake = minStake;
        m_validatorAssurance = validatorAssurance;
        m_participantRewardFraction = participantRewardFraction;
        m_validatorRewardFraction = validatorRewardFraction;
        m_balanceThreshold = balanceThreshold;

        (, uint32 electionsStartBefore, ,) = roundTimeParams();
        (uint256 curValidatorHash, , uint32 validationEnd) = getCurValidatorData();
        uint256 prevValidatorHash = getPrevValidatorHash();
        bool areElectionsStarted = now >= validationEnd - electionsStartBefore;

        Round r2 = generateRound();
        Round r1 = generateRound();
        Round r0 = generateRound();
        r0.step = RoundStep.Pooling;
        Round preR0 = generateRound();
        (r2.step, r2.completionReason, r2.unfreeze) = (RoundStep.Completed, CompletionReason.FakeRound, 0);
        (r1.step, r1.completionReason, r1.unfreeze) = (RoundStep.WaitingUnfreeze, CompletionReason.FakeRound, 0);
        r1.vsetHashInElectionPhase = areElectionsStarted? curValidatorHash : prevValidatorHash;
        setRound(preR0.id, preR0);
        setRound(r0.id, r0);
        setRound(r1.id, r1);
        setRound(r2.id, r2);
    }

    /*
     * modifiers
     */

    // Check that caller is any contract (not external message).
    modifier onlyInternalMessage {
        require(msg.sender != address(0), Errors.IS_EXT_MSG);
        _;
    }

    // Check that caller is DePool itself.
    modifier selfCall {
        require(msg.sender == address(this), Errors.IS_NOT_DEPOOL);
        _;
    }

    /* ---------- Miscellaneous private functions ---------- */

    /// @notice Helper function to return unused tons back to caller contract.
    function _returnChange() private pure {
        msg.sender.transfer(0, false, 64);
    }

    /// @dev Generates a message with error code and parameter sent back to caller contract.
    /// @param errcode Error code.
    /// @param comment Additional parameter according to error code.
    function _sendError(uint32 errcode, uint64 comment) private {
        IParticipant(msg.sender).receiveAnswer{value:0, bounce: false, flag: 64}(errcode, comment);
    }

    /// @dev Sends a message with success status to participant and returns change.
    function sendAcceptAndReturnChange() private {
        IParticipant(msg.sender).receiveAnswer{value: 0, bounce: false, flag: 64}(STATUS_SUCCESS, 0);
    }

    /// @dev Sends a message with success status to participant and returns change.
    function sendAcceptAndReturnChange128(uint64 fee) private {
        tvm.rawReserve(address(this).balance - fee, 0);
        IParticipant(msg.sender).receiveAnswer{value: 0, bounce: false, flag: 128}(STATUS_SUCCESS, 0);
    }

    /*
     *  Round functions
     */

    function setLastRoundInfo(Round round) internal {
        LastRoundInfo info = LastRoundInfo({
            supposedElectedAt: round.supposedElectedAt,
            participantRewardFraction: m_participantRewardFraction,
            validatorRewardFraction: m_validatorRewardFraction,
            participantQty: round.participantQty,
            roundStake: round.stake,
            validatorWallet: m_validatorWallet,
            validatorPubkey: tvm.pubkey(),
            validatorAssurance: m_validatorAssurance,
            reward: round.grossReward,
            reason: uint8(round.completionReason),
            isDePoolClosed: m_poolClosed
        });
        lastRoundInfo[false] = info;
    }

    function startRoundCompleting(Round round, CompletionReason reason) private returns (Round) {
        round.completionReason = reason;
        round.handledStakesAndRewards = 0;
        round.validatorRemainingStake = 0;

        if (round.participantQty == 0) {
            round.step = RoundStep.Completed;
            this.ticktock{value: VALUE_FOR_SELF_CALL, bounce: false}();
        } else {
            round.step = RoundStep.Completing;
            this.completeRound{flag: 1, bounce: false, value: VALUE_FOR_SELF_CALL}(round.id, round.participantQty);
        }

        emit RoundCompleted(toTruncatedRound(round));
        setLastRoundInfo(round);

        return round;
    }

    function cutWithdrawalValue(InvestParams p) private view returns (optional(InvestParams), uint64) {
        uint64 periodQty = (uint64(now) - p.lastWithdrawalTime) / p.withdrawalPeriod;
        uint64 withdrawal = math.min(periodQty * p.withdrawalValue, p.amount);
        p.amount -= withdrawal;
        if (p.amount < m_minStake) {
            withdrawal += p.amount;
            p.amount = 0;
        }
        p.lastWithdrawalTime += periodQty * p.withdrawalPeriod;
        optional(InvestParams) opt;
        opt.set(p);
        return (opt, withdrawal);
    }

    /// @param round2 Completing round for any reason (elector return reward, loose elections, etc.)
    /// @param round0 Round that is in pooling state
    /// @param addr Participant address from completed round
    /// @param stakes Participant stake in completed round
    function _returnOrReinvestForParticipant(
        Round round2,
        Round round0,
        address addr,
        StakeValue stakes,
        bool isValidator
    ) private returns (Round, Round) {
        uint64 stakeSum = stakeSum(stakes);
        bool stakeIsLost = round2.completionReason == CompletionReason.ValidatorIsPunished;
        optional(Participant) optParticipant = fetchParticipant(addr);
        require(optParticipant.hasValue(), InternalErrors.ERROR511);
        Participant participant = optParticipant.get();
        --participant.roundQty;
        uint64 lostFunds = stakeIsLost? (round2.stake - round2.unused) - round2.recoveredStake : 0;

        // upd ordinary stake
        uint64 newStake;
        uint64 reward;
        if (stakeIsLost) {
            if (isValidator) {
                newStake = stakes.ordinary;
                uint64 delta = math.min(newStake, lostFunds);
                newStake -= delta;
                lostFunds -= delta;
                round2.validatorRemainingStake = newStake;
            } else {
                newStake = math.muldiv(
                    round2.unused + round2.recoveredStake - round2.validatorRemainingStake,
                    stakes.ordinary,
                    round2.stake - round2.validatorStake
                );
            }
        } else {
            reward = math.muldiv(stakeSum, round2.rewards, round2.stake);
            participant.reward += reward;
            newStake = stakes.ordinary + reward;
        }
        round2.handledStakesAndRewards += newStake;

        // upd vesting
        optional(InvestParams) newVesting = stakes.vesting;
        if (newVesting.hasValue()) {
            InvestParams params = newVesting.get();
            if (stakeIsLost) {
                if (isValidator) {
                    uint64 delta = math.min(params.amount, lostFunds);
                    params.amount -= delta;
                    lostFunds -= delta;
                    round2.validatorRemainingStake += params.amount;
                } else {
                    params.amount = math.muldiv(
                        round2.unused + round2.recoveredStake - round2.validatorRemainingStake,
                        params.amount,
                        round2.stake - round2.validatorStake
                    );
                }
            }
            round2.handledStakesAndRewards += params.amount;
            uint64 withdrawalVesting;
            (newVesting, withdrawalVesting) = cutWithdrawalValue(params);
            newStake += withdrawalVesting;
        }

        // pause stake and newStake
        uint64 attachedValue = 1;
        uint64 curPause = math.min(participant.withdrawValue, newStake);
        attachedValue += curPause;
        participant.withdrawValue -= curPause;
        newStake -= curPause;
        if (newStake < m_minStake) { // whole stake is transferred to the participant
            attachedValue += newStake;
            newStake = 0;
        }

         // upd lock
        optional(InvestParams) newLock = stakes.lock;
        if (newLock.hasValue()) {
            InvestParams params = newLock.get();
            if (stakeIsLost) {
                if (isValidator) {
                    uint64 delta = math.min(params.amount, lostFunds);
                    params.amount -= delta;
                    lostFunds -= delta;
                    round2.validatorRemainingStake += params.amount;
                } else {
                    params.amount = math.muldiv(
                        round2.unused + round2.recoveredStake - round2.validatorRemainingStake,
                        params.amount,
                        round2.stake - round2.validatorStake
                    );
                }
            }
            round2.handledStakesAndRewards += params.amount;
            uint64 withdrawalLock;
            (newLock, withdrawalLock) = cutWithdrawalValue(params);
            if (withdrawalLock != 0) {
                params.owner.transfer(withdrawalLock, false, 1);
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

            if (!participant.reinvest) {
                attachedValue += newStake;
                newStake = 0;
            }
            (round0, participant) = _addStakes(round0, participant, addr, newStake, newVesting, newLock);
        }

        _setOrDeleteParticipant(addr, participant);
        IParticipant(addr).onRoundComplete{value: attachedValue, bounce: false}(
            round2.id,
            reward,
            stakes.ordinary,
            stakes.vesting.hasValue() ? stakes.vesting.get().amount : 0,
            stakes.lock.hasValue() ? stakes.lock.get().amount : 0,
            participant.reinvest,
            uint8(round2.completionReason)
        );

        return (round0, round2);
    }

    /// @dev Internal routine for reinvesting stakes of completed round to last round.
    /// Iterates over stakes of completed round no more than MAX_MSGS_PER_TR times.
    /// Sets round step to STEP_COMPLETING if there are more stakes than MAX_MSGS_PER_TR.
    /// Otherwise sets step to STEP_COMPLETED.
    /// @param round2 Round structure that should be completed.
    function _returnOrReinvest(Round round2, uint8 chunkSize) private returns (Round) {
        tvm.accept();

        Round round0 = getRound0();
        uint startIndex = 0;
        if (!round2.isValidatorStakeCompleted) {
            round2.isValidatorStakeCompleted = true;
            optional(StakeValue) optStake = round2.stakes.fetch(m_validatorWallet);
            if (optStake.hasValue()) {
                StakeValue stake = optStake.get();
                startIndex = 1;
                delete round2.stakes[m_validatorWallet];
                (round0, round2) = _returnOrReinvestForParticipant(round2, round0, m_validatorWallet, stake, true);
            }
        }

        for (uint i = startIndex; i < chunkSize && !round2.stakes.empty(); ++i) {
            (address addr, StakeValue stake) = round2.stakes.delMin().get();
            (round0, round2) = _returnOrReinvestForParticipant(round2, round0, addr, stake, false);
        }

        setRound0(round0);
        if (round2.stakes.empty()) {
            round2.step = RoundStep.Completed;
            this.ticktock{value: VALUE_FOR_SELF_CALL, bounce: false}();
        }
        return round2;
    }

    /*
     * Public Functions
     */


    /// @dev Add the participant stake in 'round0'.
    /// @param stake Value of participant's stake in nanotons.
    function addOrdinaryStake(uint64 stake) public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        uint64 msgValue = uint64(msg.value);
        if (msgValue < uint(stake) + STAKE_FEE) {
            return _sendError(STATUS_FEE_TOO_SMALL, STAKE_FEE);
        }
        uint64 fee = msgValue - stake;
        if (stake < m_minStake) {
            return _sendError(STATUS_STAKE_TOO_SMALL, m_minStake);
        }

        Participant participant = getOrCreateParticipant(msg.sender);
        Round round = getRound0();
        optional(InvestParams) empty;
        (round, participant) = _addStakes(round, participant, msg.sender, stake, empty, empty);
        setRound0(round);
        _setOrDeleteParticipant(msg.sender, participant);

        sendAcceptAndReturnChange128(fee);
    }

    /// @dev Function remove 'withdrawValue' from participant's ordinary stake only from pooling round.
    /// If ordinary stake becomes less than minStake, then the whole stake is send to participant.
    function withdrawFromPoolingRound(uint64 withdrawValue) public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(Participant) optParticipant = fetchParticipant(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        Participant participant = optParticipant.get();

        uint64 removedPoolingStake;
        (removedPoolingStake, participant) = withdrawStakeInPoolingRound(participant, msg.sender, withdrawValue, m_minStake);
        _setOrDeleteParticipant(msg.sender, participant);
        msg.sender.transfer(removedPoolingStake, false, 64);
    }

    /// @dev Add vesting for participant in 'round0'.
    /// @param beneficiary Contract address for vesting.
    /// @param totalPeriod Total period of vesting in seconds after which beneficiary becomes owner of the whole stake.
    /// @param withdrawalPeriod The period in seconds after which a part of the vesting becomes available for beneficiary.
    function addVestingStake(uint64 stake, address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod) public {
        addVestingOrLock(stake, beneficiary, withdrawalPeriod, totalPeriod, true);
    }

    function addLockStake(uint64 stake, address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod) public {
        addVestingOrLock(stake, beneficiary, withdrawalPeriod, totalPeriod, false);
    }

    function addVestingOrLock(uint64 stake, address beneficiary, uint32 withdrawalPeriod, uint32 totalPeriod, bool isVesting) private {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        if (!beneficiary.isStdAddrWithoutAnyCast() || beneficiary == address(0))
            return _sendError(STATUS_INVALID_ADDRESS, 0);

        if (msg.sender == beneficiary)
            return _sendError(STATUS_INVALID_BENEFICIARY, 0);


        uint64 msgValue = uint64(msg.value);
        if (msgValue < uint(stake) + STAKE_FEE) {
            return _sendError(STATUS_FEE_TOO_SMALL, STAKE_FEE);
        }
        uint64 fee = msgValue - stake;

        uint64 halfStake = stake / 2;
        if (halfStake < m_minStake) {
            return _sendError(STATUS_STAKE_TOO_SMALL, 2 * m_minStake);
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

        Participant participant = getOrCreateParticipant(beneficiary);
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

        for (uint i = 0; i < 2; ++i) {
            bool isFirstPart = i == 0;
            InvestParams vestingOrLock = InvestParams({
                amount: isFirstPart? halfStake : stake - halfStake,
                lastWithdrawalTime: uint64(now),
                withdrawalPeriod: withdrawalPeriod,
                withdrawalValue: withdrawalValue,
                owner: msg.sender
            });

            optional(InvestParams) v;
            optional(InvestParams) l;
            if (isVesting) {
                v.set(vestingOrLock);
            } else {
                l.set(vestingOrLock);
            }

            Round round = isFirstPart? getRoundPre0() : getRound0();
            (round, participant) = _addStakes(round, participant, beneficiary, 0, v, l);
            isFirstPart? setRoundPre0(round) : setRound0(round);
        }

        _setOrDeleteParticipant(beneficiary, participant);
        sendAcceptAndReturnChange128(fee);
    }

    /// @dev Allows a participant to withdraw some value from DePool. This function withdraws 'withdrawValue' nanotons
    /// when rounds are completed.
    /// If participant stake becomes less than 'minStake', then the whole stake is sent to participant.
    function withdrawPart(uint64 withdrawValue) public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(Participant) optParticipant = fetchParticipant(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        Participant participant = optParticipant.get();

        participant.withdrawValue = withdrawValue;
        _setOrDeleteParticipant(msg.sender, participant);
        sendAcceptAndReturnChange();
    }

    /// @dev Set some global flag for participant that indicated to return participant's ordinary stake after
    // completing rounds.
    function withdrawAll() public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(Participant) optParticipant = fetchParticipant(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        Participant participant = optParticipant.get();

        participant.reinvest = false;
        _setOrDeleteParticipant(msg.sender, participant);
        sendAcceptAndReturnChange();
    }

    /// Cancel effect of calls of functions withdrawAll and withdrawPart.
    function cancelWithdrawal() public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        optional(Participant) optParticipant = fetchParticipant(msg.sender);
        if (!optParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        Participant participant = optParticipant.get();

        participant.reinvest = true;
        participant.withdrawValue = 0;
        _setOrDeleteParticipant(msg.sender, participant);
        sendAcceptAndReturnChange();
    }


    /// @dev Allows to move amount of ordinary stake from msg.sender participant to dest participant inside DePool storage.
    /// @param dest Stake beneficiary.
    /// @param amount Stake value transferred to dest in nanotons.
    /// Use amount=0 to transfer the whole stake.
    function transferStake(address dest, uint64 amount) public onlyInternalMessage {
        if (m_poolClosed) {
            return _sendError(STATUS_DEPOOL_CLOSED, 0);
        }

        // target address should be set.
        if (!dest.isStdAddrWithoutAnyCast() || dest.isStdZero())
            return _sendError(STATUS_INVALID_ADDRESS, 0);

        // check self transfer
        address src = msg.sender;
        if (src == dest)  {
            return _sendError(STATUS_TRANSFER_SELF, 0);
        }

        if (src == m_validatorWallet || dest == m_validatorWallet) {
            return _sendError(STATUS_TRANSFER_TO_OR_FROM_VALIDATOR, 0);
        }

        optional(Participant) optSrcParticipant = fetchParticipant(src);
        if (!optSrcParticipant.hasValue()) {
            return _sendError(STATUS_NO_PARTICIPANT, 0);
        }
        Participant srcParticipant = optSrcParticipant.get();

        if (amount == 0) {
            amount = DePoolLib.MAX_UINT64;
        }

        Participant destParticipant = getOrCreateParticipant(dest);

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
        sendAcceptAndReturnChange();
    }

    // This function has the same function id as function `process_new_stake` in elector contract, 
    // because validator can send request to DePool or to election contract using same interface.
    function participateInElections(
        uint64 queryId,
        uint256 validatorKey,
        uint32 stakeAt,
        uint32 maxFactor,
        uint256 adnlAddr,
        bytes signature
    ) public functionID(0x4E73744B) onlyValidatorContract {
        if (m_poolClosed)
            return _sendError(STATUS_DEPOOL_CLOSED, 0);

        tvm.accept();
        if (checkPureDePoolBalance()) {
            Round round = getRound1();
            if (round.step != RoundStep.WaitingValidatorRequest)
                return _sendError(STATUS_NO_ELECTION_ROUND, 0);
            if (stakeAt != round.supposedElectedAt)
                return _sendError(STATUS_INVALID_ELECTION_ID, 0);
            round.validatorRequest = Request(queryId, validatorKey, stakeAt, maxFactor, adnlAddr, signature);
            _sendElectionRequest(round.proxy, round.id, round.stake, round.validatorRequest, round.elector);
            round.step = RoundStep.WaitingIfStakeAccepted;
            setRound1(round);
        }
        _returnChange();
    }

    function generateRound() internal returns (Round) {
        Request req;
        Round r = Round({
            id: m_roundQty,
            supposedElectedAt: 0, // set when round in elections phase
            unfreeze: DePoolLib.MAX_TIME, // set when round in unfreeze phase
            stakeHeldFor: 0,
            vsetHashInElectionPhase: 0, // set when round in elections phase
            step: RoundStep.PrePooling,
            completionReason: CompletionReason.Undefined,

            stake: 0,
            recoveredStake: 0,
            unused: 0,
            isValidatorStakeCompleted: false,
            grossReward: 0,
            rewards: 0,
            participantQty : 0,
            validatorStake: 0,
            validatorRemainingStake: 0,
            handledStakesAndRewards: 0,

            validatorRequest: req,
            elector: address(0), // set when round in elections phase
            proxy: getProxy(m_roundQty)
        });
        ++m_roundQty;
        return r;
    }

    function updateRound2(
        Round round2,
        uint256 prevValidatorHash,
        uint256 curValidatorHash,
        uint32 validationStart
    )
        private returns (Round)
    {

        if (round2.step == RoundStep.WaitingValidatorRequest) {
            // Next validation is started. Round is expired because no request from validator or proxy
            // rejected request. See onBounce function.
            round2.step = RoundStep.WaitingUnfreeze;
            if (round2.completionReason == CompletionReason.Undefined) {
                round2.completionReason = CompletionReason.NoValidatorRequest;
            }
            round2.unfreeze = 0;
        } else if (round2.step == RoundStep.Completing) {
            this.completeRoundWithChunk{bounce: false}(round2.id, 1);
            // For situations when there exists stake with value==V, but DePool balance == (V - epsilon)
            // In such situations some extra funds must be sent to DePool balance (See function 'receiveFunds')
        }

        // try to update unfreeze time
        if (round2.vsetHashInElectionPhase != curValidatorHash &&
            round2.vsetHashInElectionPhase != prevValidatorHash &&
            round2.unfreeze == DePoolLib.MAX_TIME
        )
        {
            // at least 1 validation period is skipped
            round2.unfreeze = validationStart + round2.stakeHeldFor;
        }

        // try to complete round
        if (now >= uint(round2.unfreeze) + DePoolLib.ELECTOR_UNFREEZE_LAG) {
            if (round2.step == RoundStep.WaitingUnfreeze &&
                round2.completionReason != CompletionReason.Undefined
            )
            {
                round2 = startRoundCompleting(round2, round2.completionReason);
            } else if (
                round2.step == RoundStep.WaitingValidationStart ||
                round2.step == RoundStep.WaitingUnfreeze
            )
            {
                // recover stake and complete round
                round2.step = RoundStep.WaitingReward;
                _recoverStake(round2.proxy, round2.id, round2.elector);
            }
        }
        return round2;
    }

    function isEmptyRound(Round round) private pure returns (bool) {
        return round.step == RoundStep.Completed || round.stake == 0;
    }

    function updateRounds() private {
        (, uint32 electionsStartBefore,,) = roundTimeParams();
        (uint256 curValidatorHash, uint32 validationStart, uint32 validationEnd) = getCurValidatorData();
        uint256 prevValidatorHash = getPrevValidatorHash();
        bool areElectionsStarted = now >= validationEnd - electionsStartBefore;
        Round roundPre0 = getRoundPre0(); // round is in pre-pooling phase
        Round round0    = getRound0(); // round is in pooling phase
        Round round1    = getRound1(); // round is in election or validation phase
        Round round2    = getRound2(); // round is in validation or investigation round

        // Try to return remaining balance to validator and delete account
        if (m_poolClosed && isEmptyRound(round2) && isEmptyRound(round1) && isEmptyRound(round0) && isEmptyRound(roundPre0) ) {
            selfdestruct(m_validatorWallet);
            tvm.exit();
        }

        round2 = updateRound2(round2, prevValidatorHash, curValidatorHash, validationStart);

        // New validator set is set. Let's recover stake to know if we won the elections
        if (round1.step == RoundStep.WaitingValidationStart &&
            round1.vsetHashInElectionPhase == prevValidatorHash
        )
        {
            round1.step = RoundStep.WaitingIfValidatorWinElections;
            _recoverStake(round1.proxy, round1.id, round1.elector);
        }

        // try to switch rounds
        if (areElectionsStarted && // elections are started
            round1.vsetHashInElectionPhase != curValidatorHash && // and pooling round is not switched to election phase yet
            round2.step == RoundStep.Completed // and round2 completed (stakes are reinvested to pooling round)
        ) {
            // we need to rotate rounds
            delete m_rounds[round2.id];
            round2 = round1;
            round1 = round0;
            round0 = roundPre0;
            roundPre0 = generateRound();

            // upd round2
            round2 = updateRound2(round2, prevValidatorHash, curValidatorHash, validationStart);

            // upd round1
            if (!m_poolClosed) {
                round1.supposedElectedAt = validationEnd;
                round1.elector = getElector();
                round1.vsetHashInElectionPhase = curValidatorHash;
                (, , ,uint32 stakeHeldFor) = roundTimeParams();
                round1.stakeHeldFor = stakeHeldFor;
                // check that validator wallet made a necessary minimal stake in round
                round1.validatorStake = stakeSum(round1.stakes[m_validatorWallet]);
                bool isValidatorStakeOk  = round1.validatorStake >= m_validatorAssurance;
                if (!isValidatorStakeOk) {
                    round1.step = RoundStep.WaitingUnfreeze;
                    round1.completionReason = CompletionReason.ValidatorStakeIsTooSmall;
                    round1.unfreeze = 0;
                } else {
                    round1.step = RoundStep.WaitingValidatorRequest;
                    emit StakeSigningRequested(round1.supposedElectedAt, round1.proxy);
                }
            }

            // upd round0
            if (!m_poolClosed)
                round0.step = RoundStep.Pooling;
        }

        setRoundPre0(roundPre0);
        setRound0(round0);
        setRound1(round1);
        setRound2(round2);
    }

    /// @dev check pure balance
    function checkPureDePoolBalance() private returns (bool) {
        uint stakes = totalParticipantFunds(0);
        uint64 msgValue = uint64(msg.value);
        uint sum = CRITICAL_THRESHOLD + stakes + msgValue;
        if (address(this).balance < sum) {
            uint replenishment = sum - address(this).balance;
            emit TooLowDePoolBalance(replenishment);
            return false;
        }
        return true;
    }

    /// @dev Updates round states, sends election requests and accepts rewards.
    function ticktock() public override onlyInternalMessage {
        if (checkPureDePoolBalance()) {
            updateRounds();
        }

        if (msg.sender != address(this))
            _returnChange();
    }

    /// @dev Allows to return or reinvest part of stakes from completed round.
    /// Function can be called only by staking itself.
    function completeRoundWithChunk(uint64 roundId, uint8 chunkSize) public selfCall {
        tvm.accept();
        if (!(isRound2(roundId) || m_poolClosed))
            // Just return. Don't throw exception because this function is called more times than necessary.
            return;
        optional(Round) optRound = fetchRound(roundId);
        require(optRound.hasValue(), InternalErrors.ERROR519);
        Round round = optRound.get();
        if (round.step != RoundStep.Completing)
            return;

        round = _returnOrReinvest(round, chunkSize);

        if (chunkSize < MAX_MSGS_PER_TR && !round.stakes.empty()) {
            uint8 doubleChunkSize = 2 * chunkSize;
            this.completeRoundWithChunk{flag: 1, bounce: false}(
                roundId,
                doubleChunkSize < MAX_MSGS_PER_TR? doubleChunkSize : chunkSize
            );
            this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, chunkSize);
        }

        setRound(roundId, round);
    }

    function completeRound(uint64 roundId, uint32 participantQty) public selfCall {
        tvm.accept();
        require(isRound2(roundId) || m_poolClosed, InternalErrors.ERROR522);
        optional(Round) optRound = fetchRound(roundId);
        require(optRound.hasValue(), InternalErrors.ERROR519);
        Round round = optRound.get();
        require(round.step == RoundStep.Completing, InternalErrors.ERROR518);

        this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, 1);

        tvm.commit();

        // Count of messages which will be created in "else" branch. See below
        uint outActionQty = (participantQty + MAX_MSGS_PER_TR - 1) / MAX_MSGS_PER_TR;
        if (outActionQty > MAX_QTY_OF_OUT_ACTIONS) {
            // Max count of participant that can be handled at once in function completeRound
            uint32 maxQty = uint32(MAX_QTY_OF_OUT_ACTIONS) * MAX_MSGS_PER_TR;
            uint32 restParticipant = participantQty;
            // Each 'completeRound' call can handle only MAX_QTY_OF_OUT_ACTIONS*MAX_MSGS_PER_TR participants.
            // But we can call 'completeRound' only  MAX_QTY_OF_OUT_ACTIONS times.
            // So we use two limit variables for the loop.
            for (int msgQty = 0; restParticipant > 0; ++msgQty) {
                uint32 curGroup =
                    (restParticipant < maxQty || msgQty + 1 == MAX_QTY_OF_OUT_ACTIONS) ?
                    restParticipant :
                    maxQty;
                this.completeRound{flag: 1, bounce: false}(roundId, curGroup);
                restParticipant -= curGroup;
            }
        } else {
            for (uint i = 0; i < participantQty; i += MAX_MSGS_PER_TR) {
                this.completeRoundWithChunk{flag: 1, bounce: false}(roundId, MAX_MSGS_PER_TR);
            }
        }
    }


    /*
     * -------------- Public functions called by proxy contract only --------------------------
     */

    // Called by Elector in process_new_stake function if our stake is accepted in elections
    function onStakeAccept(uint64 queryId, uint32 comment, address elector) public override {
        optional(Round) optRound = fetchRound(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        require(round.id == queryId, Errors.INVALID_QUERY_ID);
        require(round.step == RoundStep.WaitingIfStakeAccepted, Errors.INVALID_ROUND_STEP);

        tvm.accept();
        round.step = RoundStep.WaitingValidationStart;
        round.completionReason = CompletionReason.Undefined;
        setRound(queryId, round);

        emit RoundStakeIsAccepted(round.validatorRequest.queryId, comment);
    }

    // Called by Elector in process_new_stake function if error occurred.
    function onStakeReject(uint64 queryId, uint32 comment, address elector) public override {
        // The return value is for logging, to catch outbound external message
        // and print queryId and comment.
        optional(Round) optRound = fetchRound(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        require(round.id == queryId, Errors.INVALID_QUERY_ID);
        require(round.step == RoundStep.WaitingIfStakeAccepted, Errors.INVALID_ROUND_STEP);

        tvm.accept();
        round.step = RoundStep.WaitingValidatorRequest;
        round.completionReason = CompletionReason.StakeIsRejectedByElector;
        setRound(queryId, round);

        emit RoundStakeIsRejected(round.validatorRequest.queryId, comment);
    }

    // Calculate part of rounds' stakes that are located in dePool balance (not transferred to elector)
    function totalParticipantFunds(uint64 ingoreRoundId) private view returns (uint64) {
        uint64 stakes = 0;
        optional(uint64, Round) pair = minRound();
        while (pair.hasValue()) {
            (uint64 id, Round round) = pair.get();
            RoundStep step = round.step;
            if (id != ingoreRoundId && step != RoundStep.Completed) {
                if (step == RoundStep.Completing) {
                    if (round.completionReason == CompletionReason.ValidatorIsPunished)
                        stakes += (round.unused + round.recoveredStake) - round.handledStakesAndRewards;
                    else {
                        stakes += (round.stake + round.rewards) - round.handledStakesAndRewards;
                    }
                } else if (
                    step == RoundStep.PrePooling ||
                    step == RoundStep.Pooling ||
                    step == RoundStep.WaitingValidatorRequest ||
                    step == RoundStep.WaitingUnfreeze && round.completionReason != CompletionReason.Undefined
                ) {
                    stakes += round.stake;
                } else {
                    stakes += round.unused;
                }
            }
            pair = nextRound(id);
        }
        return stakes;
    }

    function cutDePoolReward(uint64 reward, Round round2) private view returns (uint64) {
        uint64 balance = uint64(address(this).balance);
        // round2 is still in state WaitingRoundReward but reward is received
        uint64 roundStakes = round2.stake + totalParticipantFunds(round2.id);

        // if after sending rewards DePool balance (without round stakes) becomes less than m_balanceThreshold
        if (balance < m_balanceThreshold + roundStakes + reward) {
            uint64 dePoolReward = math.min(reward, m_balanceThreshold + roundStakes + reward - balance);
            reward -= dePoolReward;
        }
        return reward;
    }

    function acceptRewardAndStartRoundCompleting(Round round2, uint64 value) private returns (Round) {
        uint64 effectiveStake = round2.stake - round2.unused;
        uint64 reward = value - effectiveStake;
        round2.grossReward = reward;

        reward = cutDePoolReward(reward, round2);

        round2.rewards = math.muldiv(reward, m_participantRewardFraction, 100);
        // Decrease reward for all participants by fee
        round2.rewards -= math.min(round2.rewards, round2.participantQty * RET_OR_REINV_FEE);

        uint64 validatorReward = math.muldiv(reward, m_validatorRewardFraction, 100);
        if (validatorReward != 0)
            m_validatorWallet.transfer(validatorReward, false, 1);

        round2 = startRoundCompleting(round2, CompletionReason.RewardIsReceived);
        return round2;
    }

    // Called by proxy contract as answer to recover_stake request.
    function onSuccessToRecoverStake(uint64 queryId, address elector) public override {
        optional(Round) optRound = fetchRound(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        tvm.accept();
        uint64 value = uint64(msg.value) + DePoolLib.PROXY_FEE;
        if (round.step == RoundStep.WaitingIfValidatorWinElections) {
            if (value < round.stake) {
                // only part of round stake is returned - we won the election,
                // but round stake is cut-off by elector,
                // optimize a minimum round stake
                round.step = RoundStep.WaitingUnfreeze;
                round.unused = value;
            } else {
                // value +/- epsilon == round.stake, so elections are lost
                round.step = RoundStep.WaitingUnfreeze;
                round.completionReason = CompletionReason.ElectionsAreLost;
            }
        } else if (round.step == RoundStep.WaitingReward) {
            round.recoveredStake = value;
            if (value >= round.stake - round.unused) {
                round = acceptRewardAndStartRoundCompleting(round, value);
            } else {
                round = startRoundCompleting(round, CompletionReason.ValidatorIsPunished);
            }
        } else {
            revert(InternalErrors.ERROR521);
        }

        setRound(queryId, round);
    }

    function onFailToRecoverStake(uint64 queryId, address elector) public override {
        optional(Round) optRound = fetchRound(queryId);
        require(optRound.hasValue(), InternalErrors.ERROR513);
        Round round = optRound.get();
        require(msg.sender == round.proxy, Errors.IS_NOT_PROXY);
        require(elector == round.elector, Errors.IS_NOT_ELECTOR);
        tvm.accept();
        if (round.step == RoundStep.WaitingIfValidatorWinElections) {
            // DePool won elections and our stake is locked by elector.
             round.step = RoundStep.WaitingUnfreeze;
        } else if (round.step == RoundStep.WaitingReward) {
            // Validator is banned! Cry.
            round = startRoundCompleting(round, CompletionReason.ValidatorIsPunished);
        } else {
            revert(InternalErrors.ERROR521);
        }
        setRound(queryId, round);
    }

    /*
     * ----------- Owner functions ---------------------
     */

    /// @dev Allows to close pool or complete pending round.
    /// Closed pool restricts deposit stakes. Stakes in roundPre0, round0 and maybe round1 are sent to
    /// participant's wallets immediately. Stakes in other rounds will be returned when rounds are completed.
    function terminator() public {
        require(msg.pubkey() == tvm.pubkey() || msg.sender == address(this), Errors.IS_NOT_OWNER_OR_SELF_CALL);
        require(!m_poolClosed, Errors.DEPOOL_IS_CLOSED);
        m_poolClosed = true;
        tvm.commit();
        tvm.accept();

        Round roundPre0 = getRoundPre0();
        Round round0 = getRound0();
        Round round1 = getRound1();

        roundPre0 = startRoundCompleting(roundPre0, CompletionReason.PoolClosed);
        round0 = startRoundCompleting(round0, CompletionReason.PoolClosed);
        if (round1.step == RoundStep.WaitingValidatorRequest) {
            round1 = startRoundCompleting(round1, CompletionReason.PoolClosed);
        }
        emit DePoolClosed();
        setRoundPre0(roundPre0);
        setRound0(round0);
        setRound1(round1);
    }

    /*
     * Fallback function.
     */

    // function that receives funds
    function receiveFunds() public pure {
    }

    receive() external {
        if (msg.sender != address(this)) {
            _returnChange();
        }
    }

    fallback() external {
        if (msg.sender != address(this)) {
            _returnChange();
        }
    }

    onBounce(TvmSlice body) external {
        uint32 functionId = body.decode(uint32);
        bool isProcessNewStake = functionId == tvm.functionId(IProxy.process_new_stake);
        bool isRecoverStake = functionId == tvm.functionId(IProxy.recover_stake);
        if (isProcessNewStake || isRecoverStake) {
            uint64 roundId = body.decode(uint64);
            optional(Round) optRound = fetchRound(roundId);
            if (isProcessNewStake) {
                require(isRound1(roundId), InternalErrors.ERROR524);
                Round r1 = optRound.get();
                require(r1.step == RoundStep.WaitingIfStakeAccepted, InternalErrors.ERROR525);
                r1.step = RoundStep.WaitingValidatorRequest; // roll back step
                emit ProxyHasRejectedTheStake(r1.validatorRequest.queryId);
                optRound.set(r1);
            } else {
                if (isRound2(roundId)) {
                    Round r2 = optRound.get();
                    require(r2.step == RoundStep.WaitingReward, InternalErrors.ERROR526);
                    r2.step = RoundStep.WaitingUnfreeze; // roll back step
                    optRound.set(r2);
                } else if (isRound1(roundId)) {
                    Round r1 = optRound.get();
                    require(r1.step == RoundStep.WaitingIfValidatorWinElections, InternalErrors.ERROR527);
                    r1.step = RoundStep.WaitingValidationStart; // roll back step
                    optRound.set(r1);
                } else {
                    revert(InternalErrors.ERROR528);
                }
                emit ProxyHasRejectedRecoverRequest(roundId);
            }
            setRound(roundId, optRound.get());
        }
    }

    // if there is no completed round yet than returns struct with default values
    // else returns info about last completed round.
    function getLastRoundInfo() public view {
        if (lastRoundInfo.empty()) {
            LastRoundInfo info;
            IDePoolInfoGetter(msg.sender).receiveDePoolInfo(info);
        } else {
            IDePoolInfoGetter(msg.sender).receiveDePoolInfo(lastRoundInfo[false]);
        }
    }

    /*
     * Public Getters
     */

    /// @dev returns participant's information about stakes in every round.
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
        optional(Participant) optParticipant = fetchParticipant(addr);
        require(optParticipant.hasValue(), Errors.NO_SUCH_PARTICIPANT);
        Participant participant = optParticipant.get();

        reinvest = participant.reinvest;
        reward = participant.reward;
        withdrawValue = participant.withdrawValue;

        optional(uint64, Round) pair = minRound();
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
            pair = nextRound(id);
        }
    }

    // Returns DePool configuration parameters and constants.
    function getDePoolInfo() public view returns (
        bool poolClosed,
        uint64 minStake,
        uint64 validatorAssurance,
        uint8 participantRewardFraction,
        uint8 validatorRewardFraction,
        uint64 balanceThreshold,

        address validatorWallet,
        address[] proxies,

        uint64 stakeFee,
        uint64 retOrReinvFee,
        uint64 proxyFee
    )
    {
        poolClosed = m_poolClosed;
        minStake = m_minStake;
        validatorAssurance = m_validatorAssurance;
        participantRewardFraction = m_participantRewardFraction;
        validatorRewardFraction = m_validatorRewardFraction;
        balanceThreshold = m_balanceThreshold;

        validatorWallet = m_validatorWallet;
        proxies = m_proxies;

        stakeFee = STAKE_FEE;
        retOrReinvFee = RET_OR_REINV_FEE;
        proxyFee = DePoolLib.PROXY_FEE;
    }

    // Returns list of all participants
    function getParticipants() external view returns (address[] participants) {
        mapping(address => bool) used;
        optional(address, Participant) pair = m_participants.min();
        while (pair.hasValue()) {
            (address p, ) = pair.get();
            if (!used.exists(p)) {
                used[p] = true;
                participants.push(p);
            }
            pair = m_participants.next(p);
        }
    }
}
