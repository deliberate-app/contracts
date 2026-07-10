// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Argument
/// @author Michael Heuer
/// @notice A library defining the types associated with an argument.
library Argument {
    /// @notice The state of an argument.
    enum State {
        Unitialized,
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
    /// @param pro The amount of pro shares in the argument market.
    /// @param proIssued The amount of issued pro shares.
    /// @param con The amount of con shares in the argument market.
    /// @param conIssued The amount of issued con shares.
    /// @param votes The votes invested in the argument.
    /// @param fees The fees accrued by the argument.
    /// @param childsVote The votes invested in the child arguments.
    /// @param childsImpact The aggregate impact of the child arguments.
    struct Data {
        bytes32 contentURI; //      ]  32
        address creator; //         ┐  20
        bool isSupporting; //       | + 1
        State state; //             | + 1
        uint16 parentArgumentId; // | + 2
        uint16 untalliedChilds; //  | + 2
        uint48 finalizationTime; // ┘ + 6 = 32
        uint32 pro; //              ┐   4
        uint32 proIssued; //        | + 4
        uint32 con; //              | + 4
        uint32 conIssued; //        | + 4
        uint32 votes; //            | + 4
        uint32 fees; //             | + 4
        uint32 childsVote; //       ┘ + 4 = 28
        int64 childsImpact; //      ]   8
    }

    /// @notice The container holding the amounts computed for an investment into an argument market.
    /// @param voteTokensInvested The amount of vote tokens invested.
    /// @param proMint The amount of minted pro shares.
    /// @param conMint The amount of minted con shares.
    /// @param fee The fee charged for the investment.
    /// @param proSwap The amount of pro shares obtained from swapping.
    /// @param conSwap The amount of con shares obtained from swapping.
    struct Investment {
        uint32 voteTokensInvested; // ┐   4
        uint32 proMint; //            | + 4
        uint32 conMint; //            | + 4
        uint32 fee; //                | + 4
        uint32 proSwap; //            | + 4
        uint32 conSwap; //            ┘ + 4 = 24
    }
}
