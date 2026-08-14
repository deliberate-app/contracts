// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Argument
/// @author Michael Heuer
/// @notice A library defining the types associated with an argument.
library Argument {
    /// @notice The data associated with an argument.
    /// @dev An argument's lifecycle is not stored: it exists once it has a `creator`, and it is final (locked
    /// in, tradeable, tallied) once its editing window (`finalizationTime`) has elapsed. The thesis sets its
    /// finalization time to creation, so it is final from the start.
    /// @param contentURI The URI pointing to the content of the argument.
    /// @param creator The creator of the argument; the zero address marks a nonexistent argument.
    /// @param isSupporting Whether the argument supports or opposes its parent.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param untalliedChilds The number of untallied child arguments.
    /// @param finalizationTime The time from which the argument is final.
    /// @param pro The pro share reserve of the rating market (scarce pro = high approval).
    /// @param con The con share reserve of the rating market.
    /// @param votes The vote tokens collateralizing the rating market (deposit and net stakes).
    /// @param subtreeVotes Tally-time state: accumulates the tallied children's subtree stakes, and holds the
    /// argument's full subtree stake (own time-weighted stake included) once the argument itself is tallied.
    /// Zero until the tally.
    /// @param descendantsAggregate The tallied children's sways as a running mean, each child weighted by its
    /// subtree stake - a sway is the child's rating clamped at zero, negated if it attacks, so the aggregate
    /// moves toward a side only on positive conviction.
    /// @param rating The tallied rating, written by the tally: signed, negative meaning refuted, and the value
    /// the argument's shares settle against at redemption. Zero until the tally. Stored beside the tally-time
    /// state it shares a slot with - `subtreeVotes` is repurposed by the tally, so re-deriving the rating
    /// later would double-count the argument's own stake.
    /// @param centeredApprovalSeconds The centered approval multiplied by the seconds it stood, accumulated
    /// over the rating window. The tally divides by the window to read the time-weighted approval: a price is
    /// bought by holding it, not by having the last word. Bounded by the full-scale approval (2^32) times a
    /// uint48 window - below 2^80, comfortably inside 88 bits.
    /// @param votesSeconds The market stake multiplied by the seconds it was held, accumulated over the rating
    /// window. The tally divides by the window to read the time-weighted stake: weight is earned by exposure,
    /// so the deposit (standing the whole window) counts in full while late stakes count in proportion.
    /// Bounded like `centeredApprovalSeconds`.
    /// @param lastAccrualTime The time up to which the two accumulators are complete; zero until the first
    /// accrual, which opens the window at the end of the editing phase.
    /// @param fees The fees accrued by the argument for its creator. Packed with the accrual state its writes
    /// coincide with (both move on stakes), leaving the tally's slot to the tally's own outputs.
    struct Data {
        bytes32 contentURI; //      ]  32
        address creator; //         ┐  20
        bool isSupporting; //       | + 1
        uint16 parentArgumentId; // | + 2
        uint16 untalliedChilds; //  | + 2
        uint48 finalizationTime; // ┘ + 6 = 31
        uint32 pro; //              ┐   4
        uint32 con; //              | + 4
        uint32 votes; //            | + 4
        uint32 subtreeVotes; //     | + 4
        int64 descendantsAggregate; // | + 8
        int64 rating; //            ┘ + 8 = 32
        int88 centeredApprovalSeconds; // ┐  11
        uint88 votesSeconds; //           | +11
        uint48 lastAccrualTime; //        | + 6
        uint32 fees; //                   ┘ + 4 = 32
    }

    /// @notice The container holding the amounts computed for a stake on an argument's rating market.
    /// @param isPro Whether the stake buys pro or con shares.
    /// @param voteTokensStaked The amount of vote tokens staked.
    /// @param fee The fee charged for the stake, accruing to the argument's creator.
    /// @param sharesOut The amount of shares the staker receives.
    struct Stake {
        bool isPro; //              ┐   1
        uint32 voteTokensStaked; // | + 4
        uint32 fee; //              | + 4
        uint32 sharesOut; //        ┘ + 4 = 13
    }
}
