// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {EnumerableSet} from "@openzeppelin-contracts-5.6.1/utils/structs/EnumerableSet.sol";

import {Argument} from "./Argument.sol";

/// @title Debate
/// @author Michael Heuer
/// @notice A library defining the debate type and helper functions operating on it.
library Debate {
    /// @notice The data associated with a debate.
    /// @param arguments The arguments of the debate by their ID.
    /// @param totalVotes The total votes cast in the debate.
    /// @param argumentsCount The number of arguments in the debate.
    /// @param participantsCount The number of accounts that joined the debate - the `N` in the bounty payout.
    /// @param leafArgumentIds The IDs of the leaf arguments of the debate tree.
    struct Data {
        mapping(uint16 argumentId => Argument.Data) arguments;
        uint32 totalVotes; //                     ┐   4
        uint16 argumentsCount; //                 | + 2
        uint32 participantsCount; //              | + 4
        EnumerableSet.UintSet leafArgumentIds; // ┘ = 10
    }

    /// @notice Increments the argument counter of a debate.
    /// @param debate The debate to increment the argument counter of.
    function incrementArgumentCounter(Data storage debate) internal {
        debate.argumentsCount += 1;
    }

    /// @notice Increments the participant counter of a debate.
    /// @param debate The debate to increment the participant counter of.
    function incrementParticipantCounter(Data storage debate) internal {
        debate.participantsCount += 1;
    }

    /// @notice Returns the number of arguments of a debate.
    /// @param debate The debate to query.
    /// @return argumentsCount The number of arguments of the debate.
    function getArgumentsCount(Data storage debate) internal view returns (uint16 argumentsCount) {
        argumentsCount = debate.argumentsCount;
    }
}
