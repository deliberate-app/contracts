//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Counters} from "@openzeppelin/contracts/utils/Counters.sol";

/**
 * Debate Related
 */

library DebateLib {
    function incrementArgumentCounter(Debate storage _debate) internal {
        _debate.argumentsCount += 1;
    }

    function getArgumentsCount(Debate storage _debate) internal view returns (uint16) {
        return _debate.argumentsCount;
    }
}

struct Debate {
    mapping(uint16 => Argument) arguments;
    uint32 totalVotes; //            ┐   4
    uint16 argumentsCount; //        ┘ + 2 = 6
    uint16[] leafArgumentIds; //     ]  32 * x // TODO Use subgraph to keep track of leaf IDs and figure out the tally tree order. Then we might just need a bool `tallied` in the Argument
    uint16[] disputedArgumentIds; // ]  32 * y // TODO http://zxstudio.org/blog/2018/09/11/effectively-storing-arrays-in-solidity/
}

/**
 * Argument Related
 */

enum State {
    Unitialized,
    Created,
    Final,
    Disputed,
    Invalid
}

struct Argument {
    bytes32 contentURI; //      ]  32
    address creator; //         ┐  20
    bool isSupporting; //       | + 1
    State state; //             | + 1
    uint16 parentArgumentId; // | + 2
    uint16 untalliedChilds; //  | + 2
    uint64 finalizationTime; // ┘ + 8 = 32
    uint32 pro; //              ┐   4
    uint32 proIssued; //        | + 4
    uint32 con; //              | + 4
    uint32 conIssued; //        | + 4
    uint32 vote; //             | + 4
    uint32 fees; //             | + 4
    uint32 childsVote; //       ┘ + 4 = 28
    int64 childsImpact; //      ]   8
    // bool tallied // TODO Needed to replace `leafArgumentIds`
}

struct InvestmentData {
    uint32 voteTokensInvested; // ┐   4
    uint32 proMint; //            | + 4
    uint32 conMint; //            | + 4
    uint32 fee; //                | + 4
    uint32 proSwap; //            | + 4
    uint32 conSwap; //            ┘ + 4 = 24
}

/**
 * User Related
 */

enum Role {
    Unassigned,
    Participant,
    Juror
}

struct User {
    mapping(uint16 => Shares) shares; // ]  32
    Role role; //                        ┐   1
    uint32 tokens; //                    ┘ + 4 = 5
}

struct Shares {
    uint32 pro; // ┐   4
    uint32 con; // ┘ + 4 =  8
}

/**
 * Time Related
 */

enum Phase {
    Unitialized,
    Editing,
    Voting,
    Finished,
    Tallied
}

struct PhaseData {
    Phase currentPhase; //    ┐   1
    uint64 editingEndTime; // | + 8
    uint64 votingEndTime; //  | + 8
    uint64 timeUnit; //       ┘ + 8 = 25
}
