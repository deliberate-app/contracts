// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Parameters
/// @author Michael Heuer
/// @notice A library collecting the protocol parameters governing every debate.
library Parameters {
    /// @notice The vote token deposit an argument's creator pays to seed the argument's market reserves.
    uint32 internal constant _DEBATE_DEPOSIT = 10;

    /// @notice The market fee in percent, accrued to the argument's creator on every stake.
    uint32 internal constant _FEE_PERCENTAGE = 5;

    /// @notice The initial vote token balance granted to a user upon joining a debate.
    uint32 public constant INITIAL_TOKENS = 100;

    /// @notice The maximum number of arguments per debate, the thesis included.
    /// @dev Bounds the atomic tally: the whole tree must be tallyable within one block's gas (asserted by the gas
    /// benchmark test). Depth needs no bound of its own - each tree level takes one time unit of finalization
    /// latency inside the seven-time-unit editing window - so the cap effectively governs breadth.
    uint16 public constant MAX_ARGUMENTS = 1024;

    /// @notice The weight of the descendants' impact in the tally blend (one half, in `_MIX_MAX` fixed-point).
    int64 internal constant _MIX_VAL = type(int64).max / 2;

    /// @notice The fixed-point scale of the tally blend weights.
    int64 internal constant _MIX_MAX = type(int64).max;

    /// @notice The fixed-point scale of an argument's own approval impact (full approval equals `type(uint32).max`).
    int64 internal constant _MAX_APPROVAL = int64(uint64(type(uint32).max));
}
