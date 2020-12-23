pragma solidity >=0.6.0;
pragma AbiHeader expire;
pragma AbiHeader time;
import "idod.sol";

/// @title DoD smart contract. Stores text of DoD and allows to sign it.
contract DoD is IDoD {

    // Text of Declaration of Decentralization (DoD)
    string public declaration; 
    // Number of signatures
    uint64 public signatures;
    /// Address of DoD Debot.
    address public debot;

    modifier accept()  {
        require(tvm.pubkey() == msg.pubkey());
        tvm.accept();
        _;
    }

    /// @notice DoD constructor. 
    /// @param debotAddr Address of DoD debot.
    constructor(address debotAddr) public accept {
        debot = debotAddr;
        declaration = "\n\
DECLARATION OF DECENTRALIZATION\n\
\n\
**“The Want, Will, and Hopes of the People.”**\n\
\n\
— The Declaration of Independence.\n\
\n\
We, the undersigned Free TON Community, Validators and Developers, hereby\n\
announce the launch of Free TON Blockchain upon the principles and terms\n\
stated in this Declaration of Decentralization.\n\
\n\
**Free TON Blockchain**\n\
\n\
TON is a protocol proposed and developed by Dr. Nikolai Durov. We, the\n\
Free TON Developers are grateful for Nikolai’s contribution to the TON\n\
protocol and wish him to continue developing it as part of a wider community\n\
effort.\n\
\n\
Since we believe in freedom of speech, in information sharing, and in free\n\
software, we haveb decided to give the power back to the community and\n\
unanimously proclaim the launch of the Free TON blockchain and the Free TON\n\
Crystal (or TON for short) as its native token.The Free TON Crystal symbol\n\
will be (U+1F48E): 💎\n\
\n\
**Why are we launching Free TON?**\n\
\n\
On the 3rd day of January 2009, Satoshi Nakamoto wrote the following inside\n\
the Bitcoin genesis block: “Chancellor on brink of second bailout for banks”,\n\
and then launched the first decentralized money.\n\
\n\
Today, more than 10 years later, and more than ever, it is obvious that\n\
we need equal economic opportunities for The People of this world; and a new,\n\
more effective way to govern public finance — without influence from political\n\
elites.\n\
\n\
The protocol represents an opportunity to create a massively scalable network\n\
benefiting hundreds of millions of people. Centered around smart contracts\n\
with easy to use tools for developers and users, it can promote free trade,\n\
equal opportunities, censorship resistance and cooperation during\n\
an unprecedented threat from a pandemic and an economic crisis.\n\
\n\
**Free TON is being launched in stages with the following objectives:**\n\
\n\
* To allow continuous debugging and development of the Free TON protocol\n\
* To drive wide adoption of decentralized solutions by millions of users\n\
* To accommodate future development scenarios\n\
* To ensure that original protocol developers can participate once it is\n\
  permitted\n\
* To ensure uniform development of a single network and to discourage\n\
  unnecessary forking\n\
\n\
**Free TON Decentralization**\n\
\n\
Free TON, launched by the principles described in this Declaration, is deemed\n\
to be fully decentralized.\n\
\n\
The undersigned fully understand and acknowledge that any and all services,\n\
efforts, and other commitments that they declare hereunder in support\n\
of Free TON blockchain, as well as any and all TONs that they may receive\n\
as a result thereof, will only be provided after Free TON is sufficiently\n\
decentralized as described below. No undersigned party has promised any TONs\n\
to any other party in exchange for any services except those expressly\n\
described in this Declaration. Any transfer of TONs by the parties must\n\
be approved through a vote by holders of TONs until Free TON decentralization\n\
is achieved.\n\
\n\
Under the terms of this Declaration all parties agree, declare, and commit\n\
to undertake every effort possible to achieve decentralization of Free TON\n\
from day one of its main network launch as described below.\n\
\n\
The decentralization of a proof-of-stake blockchain network is achieved\n\
on many levels: protocol governance, software development, validation stakes,\n\
user interface and so on. This is how fault tolerance, collusion deterrence\n\
and censorship resistance are achieved.\n\
\n\
**Free TON becomes fully decentralized when:**\n\
\n\
A vast majority of TONs are being distributed among many users in the simplest\n\
way possible in order for them to participate in staking so as to prevent any\n\
single party from influencing network activities.\n\
\n\
Several independent Validators are participating in network consensus; and,\n\
at least 13 independent stakes are validating masterchain and workchain blocks\n\
with the requisite computer resources continuously, and such that no single\n\
validator or other party that is technically able to participate in staking\n\
has more than 1/3 of all TONs available.\n\
\n\
Several teams of Developers are working on the protocol design, including its\n\
specifications, core software, compilers, languages and interfaces.\n\
\n\
**Distribution of TONs**\n\
\n\
We have identified three groups in the community that are essential to achieve\n\
Free TON Decentralization: Users, Validators and Developers. As such, all TONs\n\
in genesis block (zero state) will be allocated into different predefined\n\
Giver contracts. TONs held by these Givers will not participate in staking\n\
or voting activities for their distribution; whereby, they shall have\n\
no effect whatsoever on network decentralization properties. Each Giver\n\
activity will be governed by Free TON holders by virtue of voting via a Soft\n\
Majority Voting (SMV) mechanism as described below.\n\
\n\
**Soft Majority Voting (SMV)**\n\
\n\
All decisions regarding distribution of TONs from Givers will be made through\n\
SMV smart contracts by current Free TON holders.\n\
\n\
**Referral Giver**\n\
\n\
A Referral Giver manages airdrops of coins to initial users through a referral\n\
program that encourages the development and distribution of applications that\n\
support different user segments. These Givers will receive 85% of all TONs.\n\
\n\
These Givers will provide direct incentives to partners who choose to promote\n\
Free TON to their user base. The referral program will be governed by a smart\n\
contract that manages and validates the terms and criteria as determined from\n\
time to time by Free TON holders via an SMV smart contract.\n\
\n\
In order to preserve decentralization network properties, the distribution\n\
of TONs from a Giver or from Givers who at the time of distribution hold/s\n\
more than 30% of all TONs, to any other party or parties, is prohibited.\n\
\n\
**Validator Giver**\n\
\n\
A Validator Giver supports decentralization by providing distribution of TONs\n\
to initial validators that will receive 5% of all TONs.\n\
\n\
Validation in Free TON will be supported through direct validator\n\
participation as well as via the DePool set of smart contracts. DePools will\n\
enable further decentralization of Free TON, and therefore are highly valued\n\
and encouraged. Validator Givers will distribute validator rewards through\n\
Validator contests. Current Free TON holders will vote for Validator contests\n\
via an SMV smart contract.\n\
\n\
While Free TON has a great on-chain governance design, recent attacks on other\n\
proof-of-stake blockchains proved that low level protocol solutions are not\n\
sufficient enough to ensure long-term decentralization when trying to preserve\n\
required network performance in proof-of-stake. A large number of users should\n\
be able to participate in staking without the pitfalls of the delegated\n\
proof-of-stake design, and so, without compromising network performance. The\n\
decentralized staking pools initiative (DePool) is designed to optimize for\n\
decentralization in the Free TON consensus protocol. A Validator Giver will\n\
support a DePool smart contract standardization by distributing additional\n\
rewards to Validators who join forces in making sure validator nodes are\n\
always available in DePools.\n\
\n\
**Developer Giver**\n\
\n\
A Developer Giver supports current and ongoing protocol research and\n\
development, as well as network maintenance by independent teams. This reserve\n\
will support developers by providing them with 10% of all TONs.\n\
\n\
Continuous and coordinated work in every aspect of the core protocol, network,\n\
its architecture, and its interface designs are essential for the\n\
decentralization and support of Free TON protocol development. A clear and\n\
transparent process will be established in order to involve the community\n\
in Free TON development through the TIP (Free TON Improvement Proposal)\n\
mechanism. TIPs are approved by the community via an SMV smart contract.\n\
\n\
Developer Givers will distribute TONs to winners of TIP implementation\n\
contests. Implementations will be subject to comments and critique. Winners\n\
will be chosen by an SMV smart contract.\n\
\n\
**Caveat: No US participation**\n\
\n\
No US citizens or companies are permitted to sign this Declaration.\n\
\n\
**How You Can Contribute**\n\
\n\
We see large interest and support from those who want to see Free TON\n\
launched. Free TON should be supported by The People in a community where\n\
everybody contributes in their own way, much like Bitcoin exists today without\n\
the direct contribution of its founder.\n\
\n\
**Soft Majority Voting**\n\
\n\
If members have no opinion and/or are reluctant to vote on a particular\n\
decision for whatever reason, which is common, the process assumes that such\n\
members are essentially neutral to or are uninterested in the subject being\n\
presented. Instead of making an attempt to force neutral or uninterested\n\
parties into making a decision to participate, SMV allows decisions to be made\n\
by those who care the most. The metric for passing a decision is the\n\
mathematical difference between the percentage of ”Yes” votes minus the\n\
percentage of ”No” votes.\n\
\n\
For example, if 10% of voters said Yes and no one said No, then the SMV\n\
principle presumes that the decision is sufficiently supported by those who\n\
care enough to vote, vis-a-vis no objections. At the same time, if all members\n\
vote then the traditional simple majority rule applies, i.e., 50% +1 vote\n\
means a decision is reached. When we connect those two dots on a graph with %\n\
of Yes and % of No axes, we get a ”soft” simple majority threshold line. For\n\
important decisions such as amendments to constitutional community documents,\n\
we can draw a «soft» super-majority threshold line. The soft majority voting\n\
mechanism will be programmed on Free TON via an SMV Smart Contract.\n\
\n\
**Signing this Declaration**\n\
\n\
By signing this Declaration, the undersigned parties agree to take an active\n\
role in one or several of these activities, thereby directly contributing\n\
to Free TON Decentralization.\n\
";
    }

    /// @notice Restrict simple transfers.
    receive() external pure {
        require(false);
    }

    /// @notice Accepts sign request from DoD debot.
    function sign() external override {
        require(msg.sender == debot, 101);
        signatures++;
        // since the DoD smc is special, it doesn't need to take fee.
        // return all value back to debot.
        msg.sender.transfer(msg.value, false, 2);
    }

}