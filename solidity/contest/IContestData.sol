pragma solidity >= 0.6.0;

interface IContestData {

    /* General contest information */
    struct ContestInfo {
        uint32 gid;         // Contract global ID
        string title;       // Title of the cotract
        string link;        // Link to the document location
        uint hash;          // Hash of the proposal
    }

    /* Set of jurors */
    struct Jury {
        uint8 nJurors;       // Total number of jurors 
        uint[] keys;         // Public keys of the jurors
        address[] addresses; // Jurors' addresses
    }

    /* Timeline of the contest */
    struct ContestTimeline {
        uint32 createdAt;     // Contest contract creation
        uint32 contestStarts; // Accepts contest entries
        uint32 contestEnds;   // End of the acceptance period
        uint32 votingEnds;    // End of the voting period
    }

    /* Individual contest entry */
    struct ContenderInfo {
        address addr;       // Rewards go there
        string forumLink;   // forum post link
        string fileLink;    // PDF document link
        uint hash;          // hash of the PDF
        uint32 appliedAt;   // Timestamp of the entry arrival
        address contact;    // Surf address contact (optional)
    }

    /* Rewards table */
    struct ContestRewards {
        uint8 winners;      // number of winners to be rewarded
        uint32[] rewards;   // rewards table 
    }

    /* View of the overall contest data */
    struct ContestView {
        uint32 id;
        uint8 sub;        
        uint32 status;
        address addr;
        string title;
        string link;
        uint hash;
        uint32 createdAt;
        uint32 contestStarts;
        uint32 contestEnds;
        uint32 votingEnds;
        uint8 winners;
        uint32[] rewards;
    }

}