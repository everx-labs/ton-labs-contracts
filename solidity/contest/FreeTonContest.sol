/* Free TON Contest */
pragma solidity >= 0.6.0;
pragma AbiHeader pubkey;

import "IBaseData.sol";
import "IContestData.sol";

contract FreeTonContest is IContestData {

    /*    Exception codes:   */
    uint16 constant ERROR_NOT_AUTHORIZED    = 101; // Not authorized to administer contest
    uint16 constant ERROR_INVALID_JUROR_KEY = 102; // Message requires a jury member signature
    uint16 constant ERROR_ALREADY_VOTED     = 103; // This juror has already voted for this entry
    uint16 constant ERROR_INVALID_ENTRY     = 104; // Entry not found
    uint16 constant ERROR_CONTEST_CLOSED    = 105; // Contest does not accept entries at this time
    uint16 constant ERROR_VOTING_CLOSED     = 106; // Votes are not accepted at this time
    uint16 constant ERROR_INVALID_ASSESSMENT = 107;// Assessment with this ID does not exist
    uint16 constant ERROR_DIFFERENT_CALLER = 111; // Caller is not the contract itself
    uint16 constant ERROR_NON_NATIVE_CALLER = 112; // Caller is not the one which deployed it
    uint16 constant ERROR_RESTRICTED_CALLER = 113; // Caller is not the contract and not the deployer    
    uint16 constant ERROR_NOT_FINALIZED =     114;      // Final results are not available at this time
    uint16 constant ERROR_INVALID_TIMELINE =  120;   // Contest end date can't precede contest start date
    uint16 constant ERROR_INVALID_SETUP =     121;      // Contest has not been started yet
    uint16 constant ERROR_WRONG_MARK =        124;         // Mark should be in 1 to 10 range

    /***** Contract data ******************************************** */

    /* Contest data */

    ContestInfo _info;
    ContestTimeline _tl;
    Jury _jury;

    uint16 _id;
    uint32 _globalId;

    address _deployer;
    address _peer;
    address _timer;

    mapping (uint256 => uint8) _jurors;
    
    Stage _stage;
    uint128 constant DEF_VALUE = 2e7;
    uint128 constant DEF_VALUE_COMPUTE = 3e8;

    modifier accept() {
        tvm.accept();
        _;
    }

    /* Register Contenders */

    ContenderInfo[] _contenders;
    uint16 _entryCount;

    /* Process voting */

    enum Vote { Undefined, For, Abstain, Reject }

    struct Mark {
        uint8 jurorId;
        uint16 entryId;
        Vote vt;
        uint8 score;
        string comment;
        uint32 ts;
    }

    struct Entry {
        uint16 id;
        uint8 votes;
        uint16 totalRating;
        mapping (uint8 => Mark) marks;
    }
    Entry[] _entries;    

    /* Final voting results */
    struct Assessment {
        bool status;
        uint16 avgRating;
        uint16 totalRating;
        uint8 votes;
        uint8 votesFor;
        uint8 votesAbstained;
        uint8 votesAgainst;
    }
    mapping (uint16 => Assessment) _assessments;

    struct Score {
        uint16 id;
        uint32 avgRating;
        address addr;
        uint32 reward;
    }

    mapping (uint32 => uint16) _scores;
    uint16 _passed;
    Score[] _table;
    uint32[] _rewards;
    uint8 _winnerCount;

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

    constructor(uint32 id, ContestInfo info, ContestTimeline ctl, Jury jury, ContestRewards cr) public {
        tvm.accept();
        _deployer = msg.sender;
        _globalId = id;
        _info = info;
        _jury = jury;
        for (uint8 i = 0; i < jury.keys.length; i++) {
            _jurors[jury.keys[i]] = i;
        }
        _tl = ctl;
        _winnerCount = cr.winners;
        _rewards = cr.rewards;
        _stage = Stage.Setup;
    }

    function advanceTo(Stage s) external admin {
        if (_stage >= s) {
            return;
        } 
        
        if (s == Stage.Voted && now > _tl.votingEnds) {
            this.finalizeResults{value:DEF_VALUE_COMPUTE}();
        } else if (s == Stage.Score) {
            this.computeScore{value:DEF_VALUE_COMPUTE}();
        }  else if (s == Stage.Table) {
            this.prepareTable{value:DEF_VALUE_COMPUTE}();
        }  else if (s == Stage.Rewards) {
            this.distributeRewards{value:DEF_VALUE_COMPUTE}();
        }
        _stage = s;
    }

    function _resultsFinalized() private inline view returns (bool) {
        return (_stage >= Stage.Finalize);
    }

    /* Handle entries */

    function submit(address participant, string forumLink, string fileLink, uint hash, address contact) public {
        if (_stage < Stage.Contest && now >= _tl.contestStarts) {
            _advance(Stage.Contest);
        }
        require(_stage == Stage.Contest, ERROR_CONTEST_CLOSED);

        tvm.accept();

        if (now > _tl.contestEnds) {
            this.advanceTo{value: DEF_VALUE}(Stage.Voting);
            return;
        }

        _contenders.push(ContenderInfo(participant, forumLink, fileLink, hash, uint32(now), contact));
        Entry e;
        _entries.push(e);
        _entryCount++;
    }

    function _advance(Stage s) private inline {
        _stage = s;
    }

    function _fetchJuror() private inline view returns (uint8) {
        optional(uint8) juror = _jurors.fetch(msg.pubkey());
        require(juror.hasValue(), ERROR_INVALID_JUROR_KEY);
        return juror.get();
    }

    function _fetchAssessment(uint16 id) private inline view returns (Assessment) {
        optional(Assessment) a = _assessments.fetch(id);
        require(a.hasValue(), ERROR_INVALID_ENTRY);
        return a.get();
    }

    function _recordVote(uint16 entryId, Vote vt, uint8 score, string comments) private inline {
        require(_stage == Stage.Voting, ERROR_VOTING_CLOSED);
        uint8 jurorId = _fetchJuror();
        tvm.accept();

        Entry e = _entries[entryId];
        optional(Mark) m = e.marks.fetch(jurorId);

        if (!m.hasValue()) {
            e.votes++;
            e.marks[jurorId] = Mark(jurorId, entryId, vt, score, comments, uint32(now));
            if (vt == Vote.For) {
                e.totalRating += score;
            }
            _entries[entryId] = e;
        }

        if (now > _tl.votingEnds) {
            this.advanceTo{value: DEF_VALUE_COMPUTE}(Stage.Finalize);
            return;
        }

    }

/*    function vote() {    } */

    function voteFor(uint16 id, uint8 mark, string comment) external {
        require(mark > 0 && mark <= 10, ERROR_WRONG_MARK);
        _recordVote(id, Vote.For, mark, comment);
    }

    function abstain(uint16 id, string comment) external {
        _recordVote(id, Vote.Abstain, 0, comment);
    }

    function voteAgainst(uint16 id, string comment) external {
        _recordVote(id, Vote.Reject, 0, comment);
    }

    function _assess(uint16 i) private inline returns (Assessment) {
        Entry e = _entries[i];
        uint16 totalRating;
        uint8 votes;
        uint8 votesFor;
        uint8 votesAbstained;
        uint8 votesAgainst;

        optional(uint8, Mark) pair = e.marks.min();
        while (pair.hasValue()) {
            (uint8 id, Mark m) = pair.get();
            votes++;
            if (m.vt == Vote.For) {
                votesFor++;
                totalRating += m.score;
            } else if (m.vt == Vote.Reject) {
                votesAgainst++;
            } else if (m.vt == Vote.Abstain) {
                votesAbstained++;
            } 
            pair = e.marks.next(id);            
        }

        bool status = votesAgainst * 2 <= votes;
        uint16 avgRating = votesFor > 0 ? uint16(math.muldiv(totalRating, 100, votesFor)) : 0;

        return Assessment(status, totalRating, avgRating, votes, votesFor, votesAbstained, votesAgainst);
    }

    /* Finalize results */

    function finalizeResults() external mine {
        for (uint16 i = 0; i < _entryCount; i++) {
            _assessments[i] = _assess(i);
        }
        this.advanceTo{value: DEF_VALUE_COMPUTE}(Stage.Score);
    }

    function computeScore() external mine {
        optional(uint16, Assessment) pair = _assessments.min();
        _passed = 0;
        delete _scores;
        while (pair.hasValue()) {
            (uint16 id, Assessment a) = pair.get();
            if (a.status && a.avgRating > 0) {
                _scores[a.avgRating] = id;
                _passed++;
            }
            pair = _assessments.next(id);
        }
        this.advanceTo{value: DEF_VALUE_COMPUTE}(Stage.Table);
    }

    function prepareTable() external mine {
        optional(uint32, uint16) pair = _scores.max();
        uint8 rank = 0;
        while (pair.hasValue()) {
            (uint32 rating, uint16 id) = pair.get();
            uint32 reward = (rank <= _winnerCount) ? _rewards[rank] : 0;
            _table.push(Score(id, rating, _contenders[id].addr, reward));
            rank++;
            pair = _scores.prev(rating);
        }
        this.advanceTo{value: DEF_VALUE_COMPUTE}(Stage.Rewards);
    }

    function getRewards() public view returns (uint8 winners, uint32[] rewards) {
        winners = _winnerCount;
        rewards = _rewards;
    }

    function getTable() public view returns (Score[] table) {
        table = _table;
    }

    function rewardWinner(uint8 i) external mine {
        Score winner = _table[i];
        uint128 val = uint128(winner.reward * 1e9);
        winner.addr.transfer(val, true, 0);
    }

    function distributeRewards() external mine {
        for (uint8 i = 0; i < _winnerCount; i++) {
            this.rewardWinner(i);
        }
    }

    /* to be used to retrieve information about contest */
    function getContestInfo() public view returns (ContestInfo info) {
        info = _info;
    }

    /* Warning! for experimental use only. to assumptions to bemade based on this */

    function getInfoFor(uint16 id) public view returns (ContenderInfo ci) {
        require(id < _entryCount, 113);
        ci = _contenders[id];
    }

    /* all contenders data */

    function getContendersInfo() public view returns (ContenderInfo[] info) {
        info = _contenders;
    }

    function getStats() public view returns (Stage s) {
        s = _stage;
    }

    function getContestTimeline() public view returns (ContestTimeline tl) {
        tl = _tl;
    }

    /* Contest jury */

    function getJury() public view returns (Jury jury) {
        jury = _jury;
    }

    /* getter to be used to determine if the data has been already 
     * finalized and ready to serve for eternity 
     */
    function resultsFinalized() public view returns (bool flag) {
        flag = (_stage >= Stage.Finalize);
    }


    /* As defined by the contract specification, it must be used as 
     * a reference point to determine if the entry has passed or not
     */
    function getFinalStatusFor(uint16 id) public view finals returns (bool status) {
        require(id > 0, 114);
        status = _assessments[id].status;
    }


    /* Experimantal functionality based on the final voting data
     * assigns the places for the contestants based on the criteria defined by the spec.
    /* TODO: test it */

    function getFinalRatingsTable() public view finals returns (Score[] table) {
        table = _table;
    }

    /* Final voting data as required by the contract specification 
     * only reading from _assessments must provide 
     */

    function getFinalVotingData() public view finals returns (Assessment[] data) {
        // _assessment contains the summary. written once, with no human intervention.
        //  see finalizeResults() for details

        optional(uint16, Assessment) pair = _assessments.min(); 

        while (pair.hasValue()) {
            (uint16 id, Assessment a) = pair.get();
            data.push(a);
            pair = _assessments.next(id);
        }    
      
    }

    /* Final voting data for a specific entry as required by the contract specification */
    function getFinalStatsFor(uint16 id) public view finals returns (Assessment a) {
        a = _assessments[id];
    }
}
