/* Free TON Contest */
pragma solidity >= 0.6.0;
pragma AbiHeader pubkey;
pragma msgValue 3e7;

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
    uint16 constant ERROR_NOT_FINALIZED     = 114;      // Final results are not available at this time
    uint16 constant ERROR_INVALID_TIMELINE  = 120;   // Contest end date can't precede contest start date
    uint16 constant ERROR_INVALID_SETUP     = 121;      // Contest has not been started yet
    uint16 constant ERROR_WRONG_SCORE       = 124;         // Mark should be in 1 to 10 range

    /***** Contract data ******************************************** */

    /* Contest data */

    ContestInfo _info;
    ContestTimeline _tl;

    Juror[] _jury;

    uint16 _id;
    uint32 _globalId;

    address _deployer;
    address _peer;

    mapping (uint256 => uint8) _jurors;
    
    Stage _stage;
    uint128 constant DEF_VALUE = 3e7;
    uint128 constant DEF_VALUE_COMPUTE = 2e8;

    modifier accept() {
        tvm.accept();
        _;
    }

    /* Register Contenders */

    ContenderInfo[] _entries;

    /* Process voting */

    enum VoteType { Undefined, For, Abstain, Reject }

    struct Mark {
        VoteType vt;
        uint8 score;
    }
    mapping(uint24 => Mark) _marks;    

    struct Comment {
        string comment;
        uint32 ts;
    }
    mapping(uint24 => Comment) _comments;

    /* Final voting results */

    struct FinalData {
        uint16 totalRating;
        uint32 avgRating;
        uint8 votes;
        uint8 vfor;
        uint8 abstains;
        uint8 rejects;
        uint32 ts;        
    }
    FinalData[] _finalData;

    struct Score {
        uint16 id;
        uint16 rank;
        uint32 avgRating;
        uint32 ts;
    }
    Score[] _ranking;

    struct Payout {
        uint16 id;
        address addr;
        uint32 reward;
        uint32 ts;        
    }
    Payout[] _payouts;

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
    constructor(uint32 id, ContestInfo info, ContestTimeline ctl, Juror[] jury, uint32[] cr) public {
        _deployer = msg.sender;
        _globalId = id;
        _info = info;

        _jury = jury;
        for (uint8 i = 0; i < jury.length; i++) {
            _jurors[jury[i].keys] = i;
        }
        _tl = ctl;
        _prize = cr;
        _stage = Stage.Setup;
    }

    function advanceTo(Stage s) public restricted {
        if (_stage >= s) {
            return;
        } 
        Stage next = s;
        _stage = s;

        if (next == Stage.Contest && now >= _tl.contestStarts) {
            // start the contest
        } else if (next == Stage.Vote && now >= _tl.contestEnds) {
            // finish the contest, proceed to voting
        } else if (next == Stage.Finalize && now >= _tl.votingEnds) {
            this.finalizeResults{value:DEF_VALUE_COMPUTE}();            
        } else if (next == Stage.Trial) {
            this.trial{value:DEF_VALUE_COMPUTE}();
        } else if (next == Stage.Rank) {
            this.rank{value:DEF_VALUE_COMPUTE}();
        } else if (next == Stage.Reward) {
            this.distributeRewards{value:DEF_VALUE_COMPUTE}();
        } else if (next == Stage.Finish) {

        } else if (next == Stage.Reserved) {
            s = Stage.Undefined;
        }

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
    function _mid(uint8 jid, uint16 eid) private inline pure returns (uint24) {
        return uint24(jid * (1 << 16) + eid);
    }

    function _jeid(uint24 mid) private inline pure returns (uint8, uint16) {
        uint8 jid = uint8(mid >> 16);
        uint16 eid = uint16(mid - jid * (1 << 16));
        return (jid, eid);
    }

    /* store a single vote */
    function _recordVote(uint24 mid, VoteType voteType, uint8 score, string comment) private inline {
        _marks.add(mid, Mark(voteType, score));
        _comments.add(mid, Comment(comment, _t()));
    }

    /* Process mass votes */
    function voteAll(uint16[] id, VoteType[] voteType, uint8[] score, string[] comment) external {
        require(_stage == Stage.Vote, ERROR_VOTING_CLOSED);
        uint8 jid = _jurors[msg.pubkey()]; // Check if there's a juror with this public key
        tvm.accept();
        for (uint i = 0; i < id.length; i++) {
            _recordVote(_mid(jid, id[i]), voteType[i], score[i], comment[i]);
        }
    }

    /* Process a single vote */
    function vote(uint16 id, VoteType voteType, uint8 score, string comment) external {
        require(_stage == Stage.Vote, ERROR_VOTING_CLOSED);        
        require(score >= 0 && score <= 10, ERROR_WRONG_SCORE);
        uint8 jid = _jurors[msg.pubkey()]; // Check if there's a juror with this public key
        tvm.accept();
        _recordVote(_mid(jid, id), voteType, score, comment);
    }

    /* Process the results and form the final set of raw data */
    function finalizeResults() external mine {
        for (uint16 i = 0; i < _entries.length; i++) {
            _finalData.push(_finalize(i));
        }
        advanceTo(Stage.Trial);
    }

    /* gather the necessary stats to carry on with the evaluation */
    function _finalize(uint16 eid) private inline view returns (FinalData) {
       
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
        uint32 avgRating = vfor > 0 ? (totalRating * 100 / vfor) : 0;

        return FinalData(totalRating, avgRating, votes, vfor, abstains, rejects, _t());
    }

    /* 
     * Assess the wotks according to the specified metrics and criteria.
     * This implementation applies soft majority voting (50% + 1 of all voted means reject)
     * Qualified are sorted by average score
     */

    function trial() external mine {

        /* Separate passed entries in a dictionary with the evaluation criterion -  average scores */
        mapping (uint8 => uint32) scores;
        uint8 passed;
        for (uint8 i = 0; i < _entries.length; i++) {
            FinalData fd = _finalData[i];
            if (_status(fd)) {
                scores[i] = fd.avgRating;
                passed++;
            }
        }

        /* Sort the qualified entries according to the criteria */
        for (uint8 i = 0; i < passed; i++) {
            (uint32 max, uint8 k) = (scores[i], i);
            for (uint8 j = i + 1; j < passed; j++) {
                if (scores[j] > max) {
                    (max, k) = (scores[j], j);
                }
            }
            _ranking.push(Score(k, i, max, _t()));
            delete scores[k];
        }

        advanceTo(Stage.Rank);
    }

    /* Need 50% + 1 of all the jurors voted disqualifies 
     *
     * Can be replaced with custom logic
     */

    function _status(FinalData fd) private inline pure returns (bool) {
        return (fd.rejects * 2 <= fd.votes);
    }

    /* Compose a table of the contest winners eligible for prizes */
    function rank() external mine {
        uint l = math.min(_ranking.length, _prize.length);
        for (uint i = 0; i < l; i++) {
            Score s = _ranking[i];
            _payouts.push(Payout(s.id, _entries[s.id].addr, _prize[i], _t()));
        }
        advanceTo(Stage.Reward);        
    }

    /* Distribute the rewards accoring to the table */
    function distributeRewards() external mine {
        for (uint8 i = 0; i < _payouts.length; i++) {
            this.rewardWinner(_payouts[i]);
        }
        advanceTo(Stage.Finish);
    }

    function rewardWinner(Payout p) external pure mine {
        uint128 val = uint128(p.reward * 1e9);
        p.addr.transfer(val, true, 0);
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

    /* Contestants' ranking */
    function getRanking() public view finals returns (Score[] table) {
        table = _ranking;
    }

    /* Payouts ready for distribution */
    function getPayouts() public view finals returns (Payout[] table) {
        table = _payouts;
    }


    /* Experimental functionality based on the final voting data
     * assigns the places for the contestants based on the criteria defined by the spec.



    /* to be used to retrieve information about contest */
    function getContestInfo() public view returns (ContestInfo info) {
        info = _info;
    }

    /* Warning! for experimental use only. to assumptions to bemade based on this */

    function getInfoFor(uint16 id) public view returns (ContenderInfo ci) {
        ci = _entries[id];
    }

    /* all contenders data */

    function getContendersInfo() public view returns (ContenderInfo[] info) {
        info = _entries;
    }

    function getStats() public view returns (Stage s) {
        s = _stage;
    }

    function getContestTimeline() public view returns (ContestTimeline tl) {
        tl = _tl;
    }

    /* Contest jury */

    function getJury() public view returns (Juror[] jury) {
        jury = _jury;
    }

    function getRewards() public view returns (uint32[] rewards) {
        rewards = _prize;
    }



    function getMarks() public view returns (Mark[] mk) {

        optional(uint24, Mark) pair = _marks.min();
        while (pair.hasValue()) {
            (uint24 mid, Mark m) = pair.get();
            mk.push(m);
            pair = _marks.next(mid);
        }
    }


}
