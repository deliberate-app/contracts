// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title User
/// @author Michael Heuer
/// @notice A library defining the types associated with a user in a debate.
library User {
    /// @notice The role of a user in a debate.
    enum Role {
        Unassigned,
        Participant,
        Juror
    }

    /// @notice The pro and con shares a user holds in an argument.
    /// @param pro The amount of pro shares.
    /// @param con The amount of con shares.
    struct Shares {
        uint32 pro; // ┐   4
        uint32 con; // ┘ + 4 =  8
    }

    /// @notice The data associated with a user in a debate.
    /// @param shares The shares the user holds per argument.
    /// @param role The role of the user.
    /// @param tokens The vote token balance of the user.
    struct Data {
        mapping(uint16 argumentId => Shares) shares; // ]  32
        Role role; //                                   ┐   1
        uint32 tokens; //                               ┘ + 4 = 5
    }
}
