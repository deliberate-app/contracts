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
        /// Participants rate arguments by staking vote tokens on their rating markets.
        Rating,
        /// Rating has ended; the tally aggregating argument sway leaves-to-root can run.
        Tallying,
        /// Terminal: the tally has run, the outcome is final, and argument shares can be redeemed.
        Finished
    }

    /// @notice The phase-related data of a debate.
    /// @dev Only the terminal `Finished` phase is stored (as `finished`); Editing, Rating, and Tallying follow
    /// purely from the time gates and are derived on read. An unset `editingEndTime` marks an uncreated debate.
    /// @param finished Whether the tally has run, latching the debate into the terminal `Finished` phase.
    /// @param editingEndTime The time at which the editing phase ends.
    /// @param ratingEndTime The time at which the rating phase ends.
    /// @param lockingDuration How long a new or edited argument stays a draft before it locks in.
    /// @param finishTime The time the tally ran; anchors the bounty claim window. Zero until finished.
    struct Data {
        bool finished; //          ┐   1
        uint48 editingEndTime; //  | + 6
        uint48 ratingEndTime; //   | + 6
        uint48 lockingDuration; // | + 6
        uint48 finishTime; //      ┘ + 6 = 25
    }
}
