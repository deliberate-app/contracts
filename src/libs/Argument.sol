// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Argument
/// @author Michael Heuer
/// @notice A library defining the types associated with an argument.
library Argument {
    /// @notice The stored state of an argument. Finalization is not a stored transition: a `Created` argument
    /// becomes final automatically once its editing window (`finalizationTime`) has elapsed. `Final` is reserved
    /// for the thesis, which is permanently final from creation.
    enum State {
        Uninitialized,
        Created,
        Final
    }

    /// @notice The data associated with an argument.
    /// @param contentURI The URI pointing to the content of the argument.
    /// @param creator The creator of the argument.
    /// @param isSupporting Whether the argument supports or opposes its parent.
    /// @param state The state of the argument.
    /// @param parentArgumentId The ID of the parent argument.
    /// @param untalliedChilds The number of untallied child arguments.
    /// @param finalizationTime The time at which the argument can be finalized.
    /// @param pro The pro share reserve of the argument market (scarce pro = high approval).
    /// @param con The con share reserve of the argument market.
    /// @param votes The vote tokens collateralizing the argument market (deposit and net stakes).
    /// @param fees The fees accrued by the argument for its creator.
    /// @param childsVote The votes staked on the child arguments.
    /// @param descendantsImpact The tallied impact of all descendants: each child folds its own approval and its subtree into what it adds here.
    struct Data {
        bytes32 contentURI; //      ]  32
        address creator; //         ┐  20
        bool isSupporting; //       | + 1
        State state; //             | + 1
        uint16 parentArgumentId; // | + 2
        uint16 untalliedChilds; //  | + 2
        uint48 finalizationTime; // ┘ + 6 = 32
        uint32 pro; //              ┐   4
        uint32 con; //              | + 4
        uint32 votes; //            | + 4
        uint32 fees; //             | + 4
        uint32 childsVote; //       ┘ + 4 = 20
        int64 descendantsImpact; //      ]   8
    }

    /// @notice The container holding the amounts computed for a stake on an argument market.
    /// @param isPro Whether the stake buys pro or con shares.
    /// @param voteTokensStaked The amount of vote tokens staked.
    /// @param fee The fee charged for the stake, accruing to the argument's creator.
    /// @param sharesOut The amount of shares the staker receives.
    struct Stake {
        bool isPro; //                ┐   1
        uint32 voteTokensStaked; // | + 4
        uint32 fee; //                | + 4
        uint32 sharesOut; //          ┘ + 4 = 13
    }
}
