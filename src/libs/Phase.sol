// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Phase
/// @author Michael Heuer
/// @notice A library defining the types associated with the phases of a debate.
library Phase {
    /// @notice The phase of a debate, in chronological order.
    enum Status {
        /// No debate has been created under this ID.
        Uninitialized,
        /// Participants add, alter, move, and finalize arguments beneath the thesis.
        Editing,
        /// Participants rate arguments by staking vote tokens on their argument markets.
        Rating,
        /// Rating has ended; the tally aggregating argument impact leaves-to-root can run.
        Tallying,
        /// Terminal: the tally has run, the outcome is final, and argument shares can be redeemed.
        Finished
    }

    /// @notice The phase-related data of a debate.
    /// @param currentPhase The current phase of the debate.
    /// @param editingEndTime The time at which the editing phase ends.
    /// @param ratingEndTime The time at which the rating phase ends.
    /// @param timeUnit The time unit determining the editing and rating durations.
    struct Data {
        Status currentPhase; //   ┐   1
        uint48 editingEndTime; // | + 6
        uint48 ratingEndTime; //  | + 6
        uint48 timeUnit; //       ┘ + 6 = 19
    }
}
