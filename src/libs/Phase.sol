// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Phase
/// @author Michael Heuer
/// @notice A library defining the types associated with the phases of a debate.
library Phase {
    /// @notice The phase of a debate.
    enum Status {
        Unitialized,
        Editing,
        Voting,
        Finished,
        Tallied
    }

    /// @notice The phase-related data of a debate.
    /// @param currentPhase The current phase of the debate.
    /// @param editingEndTime The time at which the editing phase ends.
    /// @param votingEndTime The time at which the voting phase ends.
    /// @param timeUnit The time unit determining the editing and voting durations.
    struct Data {
        Status currentPhase; //   ┐   1
        uint48 editingEndTime; // | + 6
        uint48 votingEndTime; //  | + 6
        uint48 timeUnit; //       ┘ + 6 = 19
    }
}
