/* Free TON Contest */
pragma ton-solidity ^0.36.0;
pragma AbiHeader pubkey;
pragma msgValue 3e7;

import "IContestData.sol";

contract FreeTonContest {

    /*    Exception codes:   */
    uint16 constant ERROR_NOT_AUTHORIZED    = 101; // Not authorized to administer contest
    uint16 constant ERROR_INVALID_JUROR_KEY = 102; // Message requires a jury member signature
    uint16 constant ERROR_ALREADY_VOTED     = 103; // This juror has already voted for this entry
    uint16 constant ERROR_INVALID_ENTRY     = 104; // Entry not found
    uint16 constant ERROR_CONTEST_CLOSED    = 105; // Contest does not accept entries at this time
    uint16 constant ERROR_VOTING_CLOSED     = 106; // Votes are not accepted at this time
    uint16 constant ERROR_DIFFERENT_CALLER =  111; // Caller is not the contract itself
    uint16 constant ERROR_NON_NATIVE_CALLER = 112; // Caller is not the one which deployed it
    uint16 constant ERROR_RESTRICTED_CALLER = 113; // Caller is not the contract and not the deployer    
    uint16 constant ERROR_NOT_FINALIZED     = 114; // Final results are not available at this time
    uint16 constant ERROR_INVALID_TIMELINE  = 120; // Contest end date can't precede contest start date
    uint16 constant ERROR_INVALID_SETUP     = 121; // Contest has not been started yet
    uint16 constant ERROR_WRONG_SCORE       = 124; // Mark should be in 1 to 10 range
    uint16 constant ERROR_ADVANCE_AHEAD     = 130; // Already at this stage or further
    uint16 constant ERROR_ADVANCE_START     = 131; // Too early to start the contest
    uint16 constant ERROR_ADVANCE_END       = 132; // Too early to end the contest
    uint16 constant ERROR_ADVANCE_VOTE_END  = 133; // Too early to end the voting period
    /* Contest data */

    ContestInfo public _contestInfo;    // Contest reference information
    ContestTimeline public _timeline;   // Contest timeline
    Juror[] public _jury;               // Jury of the contest

    address _deployer;      // Deployer contract 
    address _peer;          // Peer contract

    mapping (uint256 => uint8) public _jurors;  // Juror ID by public key
    mapping (Stage => uint32) _actualTimeline;  // Actual timeline of the contest (as opposed to the planned)

    uint32 constant JURY_COEFFICIENT = 5;  // percentage of the contest budget as a jury reward
    uint128 constant DEF_COMPUTE = 2e8;     // default value for computation-heavy operations
    uint128 constant MAX_COMPUTE = 1e9;     // maximal value for computation-heavy operations
    uint8 constant CHUNK_SIZE = 7;          // break down messaging into chunks of this much messages each

    ContenderInfo[] public _entries;        // Entries submitted to compete
    Stage public _stage;                    // Current contest stage

    enum VoteType { Undefined, For, Abstain, Reject }

    /* Incoming vote */
    struct Evaluation {
        uint8 entryId;      // entry being evaluated
        VoteType voteType;  // kind of vote: for, abstain or reject
        uint8 score;        // a mark from 1 to 10, 0 for abstain or reject
        string comment;     // juror's evaluation in the text form
    }

    /* Internal processing of the assessments - broken down into two structures for efficiency */
    // Actively used
    struct Mark {
        VoteType vt;
        uint8 score;
    }

    // Just stored
    struct Comment {   
        string comment;
        uint32 ts;
    }
    mapping (uint16 => Mark) public _marks;
    mapping (uint16 => Comment) public _comments;

    struct Stats {
        uint8 id;           // Entry or juror id
        uint16 totalRating; // Sum of all marks given
        uint16 avgRating;   // Sum of all marks multiplied by 100 and divided by the number of votes for
        uint8 votesFor;     // Votes "for"
        uint8 abstains;     // Votes "abstain"
        uint8 rejects;      // Votes "reject"
    }

    /* Final contest results and jury stats */
    Stats[] public _contestResults;
    Stats[] public _juryStatistics;

    /* Contenders or jurors ranking table */
    struct Score {
        uint8 id;           // Entry or juror id
        uint16 rating;      // Rating (multiplied by 100)
    }
    Score[] public _contestRanking;
    Score[] public _juryRanking;

    struct Payout {
        uint8 id;           // Entry or juror id
        uint16 rating;      // Rating (multiplied by 100)
        address addr;       // address of the contestant/juror
        uint32 reward;      // reward (in tons)
    }

    /* Payouts due on the contest completion */
    Payout[] public _contestPayouts;   
    Payout[] public _juryPayouts;

    /* Actual budgets for payouts, computed based on metrics */
    uint32 public _contestBudget;  // assessed value
    uint32 public _juryBudget;     // performance

    uint32[] public _prizes;    // Prize pool for the contestants

    /* Modifiers */

    // Accept messages from this contract only
    modifier mine {
        require(msg.sender == address(this), ERROR_DIFFERENT_CALLER);
        _;
    }

    // Restricted to the messages from deployer or from the contract itself
    modifier restricted {
        require(msg.sender == address(this) || msg.sender == _deployer, ERROR_RESTRICTED_CALLER);
        _;
    }

    // Can be called only after contest results have been finalized
    modifier finals {
        require(_stage >= Stage.Finalize, ERROR_NOT_FINALIZED); 
        _;
    }

    /* Contest setup */
    constructor(ContestInfo contestInfo, ContestTimeline contestTimeline, Juror[] jury, uint32[] prizes) public {
        _deployer = msg.sender;
        _contestInfo = contestInfo;
        _timeline = contestTimeline;
        _jury = jury;

        for (uint8 i = 0; i < jury.length; i++) {
            _jurors[jury[i].key] = i;
        }
        _prizes = prizes;
        _stage = Stage.Setup;
    }

    /* To be called to advance to the next stage, provided the requirements are met */
    function advanceTo(Stage s) public restricted {
        require(_stage < s, ERROR_ADVANCE_AHEAD);

        if (s == Stage.Contest) {
            require(now >= _timeline.contestStarts, ERROR_ADVANCE_START);
        } else if (s == Stage.Vote) {
            require(now >= _timeline.contestEnds, ERROR_ADVANCE_END);            
        } else if (s == Stage.Finalize) {
            require(now >= _timeline.votingEnds, ERROR_ADVANCE_VOTE_END);
            this.finalizeResults{value: MAX_COMPUTE}();
        } else if (s == Stage.Rank) {
            this.rank{value: MAX_COMPUTE}();
        } else if (s == Stage.Reward) {
            this.distributeRewards{value: MAX_COMPUTE}(0);
        } else if (s == Stage.Finish) {

        } else if (s == Stage.Reserved) {
            s = Stage.Undefined;
        }
        _stage = s;
        _actualTimeline[s] = uint32(now);
    }

    /* Record contest entries submitted by contenders */
    function submit(address participant, string forumLink, string fileLink, uint hash, address contact) external {
        require(_stage == Stage.Contest, ERROR_CONTEST_CLOSED);
        tvm.accept();
        _entries.push(ContenderInfo(participant, forumLink, fileLink, hash, contact, uint32(now)));
    }

    /* Combine juror and entry IDs to index the mark */
    function _markId(uint8 jurorId, uint8 entryId) private inline pure returns (uint16 markId) {
        markId = uint16(jurorId * (1 << 8) + entryId);
    }

    /* Break down combined ID into components - juror and entry IDs */
    function _jurorEntryIds(uint16 markId) private pure returns (uint8 jurorId, uint8 entryId) {
        jurorId = uint8(markId >> 8);      // 8 upper bits
        entryId = uint8(markId & 0xFF);    // 8 lower bits
    }

    /* Accept voting messages only with a current jury member signature, and only when the time is right */
    function _checkVote() private inline view returns (uint8) {
        require(_stage == Stage.Vote, ERROR_VOTING_CLOSED);        
        uint8 jurorId = _jurors.at(msg.pubkey()); // Check if there's a juror with this public key
        tvm.accept();        
        return jurorId;
    }

    /* Enforce score being in range 1 to 10 for regular votes and 0 for abstains and rejects */
    function _validateScore(Evaluation evaluation) private pure returns (uint8 score) {
        score = evaluation.score;
        if (evaluation.voteType == VoteType.For) {
            if (score == 0) {
                score = 1;
            } else if (score > 10) {
                score = 10;
            }
        } else {
            score = 0;
        }
    }

    /* store a single vote */
    function _recordVote(uint8 jurorId, Evaluation evaluation) private inline {
        uint16 markId = _markId(jurorId, evaluation.entryId);
        _marks.add(markId, Mark(evaluation.voteType, _validateScore(evaluation)));
        _comments.add(markId, Comment(evaluation.comment, uint32(now)));
    }

    /* Process mass votes */
    function voteAll(Evaluation[] evaluations) external {
        uint8 jurorId = _checkVote();
        for (uint8 i = 0; i < evaluations.length; i++) {
            _recordVote(jurorId, evaluations[i]);
        }
    }

    /* Process a single vote */
    function vote(Evaluation evaluation) external {
        uint8 jurorId = _checkVote(); // Check if there's a juror with this public key
        _recordVote(jurorId, evaluation);
    }

    /* Process the results and form the final set of raw data */
    function finalizeResults() external mine {
        for (uint8 i = 0; i < _entries.length; i++) {
            /* compute stats necessary to evaluate the entries based on the contest rules */            
            _contestResults.push(_computeStatsFor(i, true));
        }
        for (uint8 i = 0; i < _jury.length; i++) {
            /* compute jury activity stats */
            _juryStatistics.push(_computeStatsFor(i, false));
        }
        advanceTo(Stage.Rank);
    }

    /* Common routine for computing stats for entries and jurors */
    function _computeStatsFor(uint8 id, bool isEntry) private view returns (Stats stats) {
        uint16 totalRating;
        uint8 votesFor;
        uint8 abstains;
        uint8 rejects;
        uint16 avgRating;

        uint8 cap = isEntry ? uint8(_jury.length) : uint8(_entries.length);

        for (uint8 i = 0; i < cap; i++) {
            uint16 mid = isEntry ? _markId(i, id) : _markId(id, i);
            if (_marks.exists(mid)) {
                Mark m = _marks[mid];
                if (m.vt == VoteType.For) {
                    votesFor++;
                    totalRating += m.score;
                } else if (m.vt == VoteType.Reject) {
                    rejects++;
                } else if (m.vt == VoteType.Abstain) {
                    abstains++;
                } 
            }
        }
        avgRating = votesFor > 0 ? uint16(totalRating * 100 / votesFor) : 0;
        stats = Stats(id, totalRating, avgRating, votesFor, abstains, rejects);
    }

    /* 
     * Assess the entries quality and the jurors' performance according to the specified metrics and criteria
     */
    function rank() external mine {
        (_contestRanking, _contestPayouts, _contestBudget) = _rankContenders();
        (_juryRanking, _juryPayouts, _juryBudget) = _rankJurors();
        advanceTo(Stage.Reward);
    }

    /* Rank contenders according to the evaluations submitted by jury */
    function _rankContenders() private inline view returns (Score[] contestRanking, Payout[] contestPayouts, uint32 contestBudget) {
        mapping (uint24 => bool) scores;
        
        // Sort entries from highest average rating to lowest
        for (uint8 i = 0; i < _entries.length; i++) {
            Stats st = _contestResults[i];
            /* 50%+ of jurors rejects disqualifies */
            if (st.rejects <= st.votesFor + st.abstains) {
                uint24 key = uint24(st.avgRating) * (1 << 8) + i;
                scores[key] = true;
            }
        }
        
        /* 
         * Compose:
         * 1) a ranking table according to the ratings computed above
         * 2) a payout table derived from rankings and the prize pool 
         */
        optional(uint24, bool) curScore = scores.max();
        uint8 k = 0;
        while (curScore.hasValue()) {
            (uint24 key,) = curScore.get();
            uint16 rating = uint16(key >> 8);
            uint8 entryId = uint8(key & 0xFF);
            contestRanking.push(Score(entryId, rating));
            if (k < _prizes.length) {
                contestPayouts.push(Payout(entryId, rating, _entries[entryId].addr, _prizes[k]));
                contestBudget += _prizes[k];
            }
            k++;
            curScore = scores.prev(key);
        }
    }

    /* Rank jurors according to their contribution to the assessment. Compute due payouts based on the specified formulae  */
    function _rankJurors() private inline view returns (Score[] juryRanking, Payout[] juryPayouts, uint32 juryBudget) {
        
        /* calculate jury performance metrics */
        mapping (uint24 => uint8) scores;
        uint16 totalVotes;
        for (uint8 i = 0; i < _jury.length; i++) {
            Stats st = _juryStatistics[i];
            /* Mandatory contribution as a sum of votes for and rejects. Affects payout sum */
            uint8 contribution = _jurorContribution(st);    
            if (contribution > 0) {
                /* 
                 * Base metric of assessments' quality: total length of meaningful comments. Affects ranking.
                 * Thanks to Noam Y for the idea of the metric.
                 */
                uint16 rating = _commentsLength(i);
                uint24 key = uint24(rating * (1 << 8) + i);
                totalVotes += contribution;
                scores[key] = contribution;                
            }
        }
        uint32 votePrice = _contestBudget * JURY_COEFFICIENT / totalVotes;

        /* 
         * Compose two tables:
         * 1) ranking table based on the quality metric
         * 2) payout table based on participation metric
         */
        optional(uint24, uint8) curScore = scores.max();
        while (curScore.hasValue()) {
            (uint24 key, uint8 done) = curScore.get();
            uint16 rating = uint16(key >> 8);
            uint8 jurorId = uint8(key & 0xFF);
            juryRanking.push(Score(jurorId, rating));
            uint32 reward = votePrice * done / 100;
            juryBudget += reward;
            juryPayouts.push(Payout(jurorId, rating, _jury[jurorId].addr, reward));
            curScore = scores.prev(key);
        }
    }

    /* Assessment quality metric for the jurors ranking table */
    function _commentsLength(uint8 jurorId) private view returns (uint16 totalLength) {
        for (uint8 i = 0; i < _entries.length; i++) {
            uint16 markId = _markId(jurorId, i);
            if (_comments.exists(markId) && _marks.exists(markId) && _marks[markId].vt != VoteType.Abstain) {
                totalLength += _comments[markId].comment.byteLength();
            }
        }
    }

    /* Assess juror's contribution */
    function _jurorContribution(Stats st) private inline view returns (uint8) {
        uint8 done = st.votesFor + st.rejects;
        /* Half of the meaningful votes makes eligible for rewards */
        return (done >= _entries.length / 2) ? done : 0;
    }

    /* Distribute the rewards according to the table, starting from n-th entry */
    function distributeRewards(uint8 n) external mine {
        uint8 l = uint8(math.min(_contestPayouts.length, n + CHUNK_SIZE));
        uint8 i;
        for (i = n; i < l; i++) {
            Payout s = _contestPayouts[i];
            if (s.reward > 0) {
                s.addr.transfer(uint128(s.reward) * 1e9, true, 0);
            }
        }
        /* Distribute only to contenders for now */
        if (i < _contestPayouts.length && i < _prizes.length) {
            this.distributeRewards{value:MAX_COMPUTE}(i);
        } else {
            advanceTo(Stage.Finish);
        }
    }

    /* Stats for an entry */
    function getEntryStats(uint8 entryId) public view returns (Stats entryStats) {
        entryStats = _computeStatsFor(entryId, true);
    }

    /* Stats for a juror */
    function getJurorStats(uint8 jurorId) public view returns (Stats jurorStats) {
        jurorStats = _computeStatsFor(jurorId, false);
    }

    /* 
     * Overall contest statistics: 
     *      total points awarded by all jurors combined
     *      total number of votes
     *      average score (multiplied by 100)
     *      number of entries submitted
     *      unique jurors voted
     */
    function contestStatistics() public view returns (uint16 pointsAwarded, uint16 totalVotes, uint16 avgScore, uint8 entries, uint8 jurorsVoted) {
        uint16 totalVotesFor;
        entries = uint8(_entries.length);

        for (uint8 i = 0; i < _entries.length; i++) {
            Stats entryStats = _computeStatsFor(i, true);
            pointsAwarded += entryStats.totalRating;
            totalVotesFor += entryStats.votesFor;
            totalVotes += entryStats.votesFor + entryStats.abstains + entryStats.rejects;
        }

        for (uint8 i = 0; i < _jury.length; i++) {
            optional(uint16, Mark) nextPair = _marks.nextOrEq(_markId(i, 0));
            if (nextPair.hasValue()) {
                (uint16 nextKey, ) = nextPair.get();
                if (nextKey < _markId(i + 1, 0)) {
                    jurorsVoted++;
                }
            }
        }

        avgScore = totalVotesFor > 0 ? uint16(pointsAwarded * 100 / totalVotesFor) : 0;
    }

    /* Snapshot of the contest data */
    function getCurrentData() public view returns (ContenderInfo[] info, Juror[] jury, Stats[] allStats, mapping (uint16 => Mark) marks, mapping (uint16 => Comment) comments) {
        info = _entries;
        jury = _jury;
        for (uint8 i = 0; i < _entries.length; i++) {
            allStats.push(_computeStatsFor(i, true));
        }
        marks = _marks;
        comments = _comments;
    }

    /* Resulting contest data */
    function getFinalData() public view returns (Stats[] contestResults, Stats[] juryStatistics, Score[] contestRanking, Score[] juryRanking, 
                Payout[] contestPayouts, uint32 contestBudget, Payout[] juryPayouts, uint32 juryBudget, ContestTimeline timeline) {
        contestResults = _contestResults;
        juryStatistics = _juryStatistics;
        contestRanking = _contestRanking;
        juryRanking = _juryRanking;
        contestPayouts = _contestPayouts;
        contestBudget = _contestBudget;
        juryPayouts = _juryPayouts;
        juryBudget = _juryBudget;
        timeline = _timeline;
    }
}
