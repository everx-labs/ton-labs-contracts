pragma ton-solidity ^0.36.0;

enum Stage { Undefined, Setup, Contest, Vote, Finalize, Rank, Reward, Finish, Reserved, Last }

/* General contest information */

struct ContestInfo {
    uint32 gid;         // Contract global ID
    string title;       // Title of the contract
    string link;        // Link to the document location
    uint hashCode;      // Hash of the proposal
}

struct Juror {
    uint key;       // Juror's public key
    address addr;   // Juror's address
}

/* Timeline of the contest */
struct ContestTimeline {
    uint32 createdAt;     // Contest contract creation
    uint32 contestStarts; // Accepts contest entries
    uint32 contestEnds;   // End of the acceptance period
    uint32 votingEnds;    // End of the voting period
}

struct ContestStage {
    uint32 mask;
    uint32 notifyAt;
}

/* Individual contest entry */
struct ContenderInfo {
    address addr;       // Rewards go there
    string forumLink;   // forum post link
    string fileLink;    // PDF document link
    uint hashCode;      // hash of the PDF
    address contact;    // Surf address contact (optional)
    uint32 appliedAt;   // Timestamp of the entry arrival        
}
