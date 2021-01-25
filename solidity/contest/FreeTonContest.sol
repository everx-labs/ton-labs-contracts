/* Free TON Contest */
pragma solidity >= 0.6.0;
pragma AbiHeader pubkey;
pragma msgValue 30000000;

import "IContestData.sol";

contract FreeTonContest is IContestData {

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

    ContestInfo _info;      // Contest reference information
    ContestTimeline _tl;    // Contest timeline
    Juror[] _jury;          // Jury of the contest

    address _deployer;      // Deployer contract 
    address _peer;          // Peer contract

    mapping (uint256 => uint8) _jurors; // Juror ID by public key
    mapping (Stage => uint32) _actualTimeline;
    
    uint128 constant DEF_VALUE_COMPUTE = 2e8;
    uint128 constant MAX_VALUE_COMPUTE = 1e9;

    modifier accept() {
        tvm.accept();
        _;
    }

    ContenderInfo[] _entries;   // Entries submitted to compete
    Stage _stage;               // Current contest stage

    enum VoteType { Undefined, For, Abstain, Reject }

    // Actively used
    struct Mark {
        VoteType vt;    // For, Abstain, Reject
        uint8 score;    // 0 for abstain and reject, or a mark from 1 to 10
    }
    mapping(uint16 => Mark) _marks;

    // Just stored
    struct Comment {   
        string comment;
        uint32 ts;
    }
    mapping(uint16 => Comment) _comments;

    /* Final voting results */

    struct FinalData {
        uint16 totalRating; // Sum of all marks given
        uint16 avgRating;   // Sum of all marks multiplied by 100 and divided by the number of votes for
        uint8 votes;        // Total votes
        uint8 vfor;         // Votes "for"
        uint8 abstains;     // Votes "abstain"
        uint8 rejects;      // Votes "reject"
    }
    FinalData[] _finalData;

    struct Score {
        uint8 id;           // Entry id
        uint16 avgRating;   // Average rating (multiplied by 100)
        address addr;       // address of the contestant
        uint32 reward;      // reward (in tons)
    }
    Score[] _ranking;

    uint32[] _prize;

    /* Modifiers */

    modifier mine {
        require(msg.sender == address(this), ERROR_DIFFERENT_CALLER);
        _;
    }

    modifier admin {
        require(msg.sender == _deployer, ERROR_NON_NATIVE_CALLER);
        _;
    }

    modifier restricted {
        require(msg.sender == address(this) || msg.sender == _deployer, ERROR_RESTRICTED_CALLER);
        _;
    }

    modifier finals {
        require(_resultsFinalized(), ERROR_NOT_FINALIZED);
        _;
    }

    /* Contest setup */
    constructor(ContestInfo info, ContestTimeline ctl, Juror[] jury, uint32[] prizes) public {
        _deployer = msg.sender;
        _info = info;
        _tl = ctl;
        _jury = jury;

        for (uint8 i = 0; i < jury.length; i++) {
            _jurors[jury[i].key] = i;
        }
        _prize = prizes;
        _stage = Stage.Setup;
    }

    function advanceTo(Stage s) public restricted {
        require(_stage < s, ERROR_ADVANCE_AHEAD);

        if (s == Stage.Contest) {
            require(now >= _tl.contestStarts, ERROR_ADVANCE_START);
        } else if (s == Stage.Vote) {
            require(now >= _tl.contestEnds, ERROR_ADVANCE_END);            
        } else if (s == Stage.Finalize) {
            require(now >= _tl.votingEnds, ERROR_ADVANCE_VOTE_END);
            this.finalizeResults{value:DEF_VALUE_COMPUTE}();
        } else if (s == Stage.Rank) {
            this.rank{value:MAX_VALUE_COMPUTE}();
        } else if (s == Stage.Reward) {
            this.distributeRewards{value:DEF_VALUE_COMPUTE}();
        } else if (s == Stage.Finish) {

        } else if (s == Stage.Reserved) {
            s = Stage.Undefined;
        }
        _stage = s;
        _actualTimeline[s] = _t();
    }

    function _resultsFinalized() private inline view returns (bool) {
        return (_stage >= Stage.Finalize);
    }

    /* Handle entries */

    function submit(address participant, string forumLink, string fileLink, uint hash, address contact) public {
        require(_stage == Stage.Contest, ERROR_CONTEST_CLOSED);
        tvm.accept();
        _entries.push(ContenderInfo(participant, forumLink, fileLink, hash, contact, _t()));
    }

    /* Current timestamp */
    function _t() private inline pure returns (uint32) {
        return uint32(now);
    }

    /* Combined juror/entry id to single out a mark */
    function _mid(uint8 jid, uint8 eid) private inline pure returns (uint16) {
        return uint16(jid * (1 << 8) + eid);
    }

    function _jeid(uint16 mid) private inline pure returns (uint8, uint8) {
        return (uint8(mid >> 8), uint8(mid & 0xFF));
    }

    function _checkVote() private inline view returns (uint8) {
        require(_stage == Stage.Vote, ERROR_VOTING_CLOSED);        
        uint8 jid = _jurors.at(msg.pubkey()); // Check if there's a juror with this public key
        tvm.accept();        
        return jid;
    }

    /* store a single vote */
    function _recordVote(uint16 mid, VoteType voteType, uint8 score, string comment) private inline {
        _marks.add(mid, Mark(voteType, score));
        _comments.add(mid, Comment(comment, _t()));
    }

    /* Process mass votes */
    function voteAll(uint8[] id, VoteType[] voteType, uint8[] score, string[] comment) external {
        uint8 jid = _checkVote();
        for (uint8 i = 0; i < id.length; i++) {
            _recordVote(_mid(jid, id[i]), voteType[i], score[i], comment[i]);
        }
    }

    /* Process a single vote */
    function vote(uint8 id, VoteType voteType, uint8 score, string comment) external {
        if (voteType == VoteType.For)
            require(score > 0 && score <= 10, ERROR_WRONG_SCORE);
        else
            score = 0;            // Ignore score for rejects and abstains
        uint8 jid = _checkVote(); // Check if there's a juror with this public key
        tvm.accept();
        _recordVote(_mid(jid, id), voteType, score, comment);
    }

    /* Process the results and form the final set of raw data */
    function finalizeResults() external mine {
        for (uint8 i = 0; i < _entries.length; i++) {
            _finalData.push(_finalize(i));
        }
        advanceTo(Stage.Rank);
    }

    /* gather the necessary stats to carry on with the evaluation */
    function _finalize(uint8 eid) private inline view returns (FinalData) {
       
        uint16 totalRating;
        uint8 vfor;
        uint8 rejects;
        uint8 abstains;

        for (uint8 i = 0; i < _jury.length; i++) {

            optional(Mark) om = _marks.fetch(_mid(i, eid));
            
            if (om.hasValue()) {
                Mark m = om.get();
                if (m.vt == VoteType.For) {
                    vfor++;
                    totalRating += m.score;
                } else if (m.vt == VoteType.Reject) {
                    rejects++;
                } else if (m.vt == VoteType.Abstain) {
                    abstains++;
                } 
            } 
        }
        uint8 votes = vfor + rejects + abstains;
        uint16 avgRating = vfor > 0 ? uint16(totalRating * 100 / vfor) : 0;

        return FinalData(totalRating, avgRating, votes, vfor, abstains, rejects);
    }

    /* 
     * Assess the works according to the specified metrics and criteria.
     * This implementation applies soft majority voting (50% + 1 of all voted means reject)
     * Qualified are sorted by the average score
     */
    function rank() external mine {
        mapping (uint24 => bool) scores;
        
        // sort entries from highest average rating to lowest.
        for (uint8 i = 0; i < _entries.length; i++) {
            FinalData fd = _finalData[i];
            if (_status(fd)) {
                uint24 key = uint24(fd.avgRating) * (1 << 8) + i;
                scores[key] = true;
            }
        }

        optional(uint24, bool) curScore = scores.max();
        uint8 k = 0;
        while (curScore.hasValue()) {
            (uint24 key,) = curScore.get();
            (uint16 rating, uint8 eid) = (uint16(key >> 8), uint8(key & 0xFF));
            uint32 reward = (k <= _prize.length) ? _prize[k] : 0;
            _ranking.push(Score(eid, rating, _entries[eid].addr, reward));
            k++;
            curScore = scores.prev(key);
        }

        advanceTo(Stage.Reward);
    }

    /* Need 50% + 1 of all the jurors voted disqualifies 
     *
     * Can be replaced with custom logic
     */
    function _status(FinalData fd) private inline pure returns (bool) {
        return (fd.rejects * 2 <= fd.votes);
    }

    /* Distribute the rewards accoring to the table */
    function distributeRewards() external mine {
        uint l = math.min(_ranking.length, _prize.length);
        for (uint i = 0; i < l; i++) {
            this.rewardWinner(_ranking[i]);
        }
        advanceTo(Stage.Finish);
    }

    function rewardWinner(Score s) external pure mine {
        uint128 val = uint128(s.reward * 1e9);
        s.addr.transfer(val, true, 0);
    }

    /* getter to be used to determine if the data has been already 
     * finalized and ready to serve for eternity 
     */
    function resultsFinalized() public view returns (bool flag) {
        flag = (_stage >= Stage.Finalize);
    }


    /* Final voting data for a specific entry as required by the contract specification */
    function getFinalStatsFor(uint16 id) public view finals returns (FinalData d) {
        d = _finalData[id];
    }

    /* Final voting data as required by the contract specification 
     * only reading from _assessments must provide 
     */
    function getFinalVotingData() public view finals returns (FinalData[] data) {
        // _assessment contains the summary. written once, with no human intervention.
        //  see finalizeResults() for details
        data = _finalData;
    }

    /* Contestants' ranking and payouts */
    function getRanking() public view finals returns (Score[] table) {
        table = _ranking;
    }

    /* to be used to retrieve information about contest */
    function getContestInfo() public view returns (ContestInfo info) {
        info = _info;
    }

    /* Warning! for experimental use only. no assumptions to be made based on this */

    function getInfoFor(uint16 id) public view returns (ContenderInfo ci) {
        ci = _entries[id];
    }

    /* all contenders data */
    function getContendersInfo() public view returns (ContenderInfo[] info) {
        info = _entries;
    }

    function getContestTimeline() public view returns (ContestTimeline tl) {
        tl = _tl;
    }

    function getJury() public view returns (Juror[] jury) {
        jury = _jury;
    }

    function getRewards() public view returns (uint32[] rewards) {
        rewards = _prize;
    }

    function getActualTimeline() public view returns (Stage[] stages, uint32[] ts) {
        optional(Stage, uint32) pair = _actualTimeline.min();
        while (pair.hasValue()) {
            (Stage s, uint32 t) = pair.get();
            stages.push(s);
            ts.push(t);
            pair = _actualTimeline.next(s);
        }
    }

    function getMarks() public view returns (Mark[] mk) {
        optional(uint16, Mark) pair = _marks.min();
        while (pair.hasValue()) {
            (uint16 mid, Mark m) = pair.get();
            mk.push(m);
            pair = _marks.next(mid);
        }
    }

    function getStats() public view returns (Stage s) {
        s = _stage;
    }
}
