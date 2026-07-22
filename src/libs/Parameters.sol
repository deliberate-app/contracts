// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Parameters
/// @author Michael Heuer
/// @notice A library collecting the protocol parameters governing every debate.
library Parameters {
    /// @notice The smallest vote token deposit an argument's creator may stake to seed the market reserves.
    /// @dev The creator picks the deposit; this floor keeps both market reserves non-empty across the seedable
    /// approval range (a degenerate zero reserve would freeze the constant-product market) and sets the minimum
    /// weight an argument carries into the tally.
    uint32 internal constant _MIN_DEBATE_DEPOSIT = 10;

    /// @notice The highest market fee (in percent) a debate creator may set. Capping below 100 keeps
    /// every nonzero stake's net amount at least 1, so a stake can never degenerate into a pure fee
    /// transfer that moves no market.
    uint32 internal constant _MAX_FEE_PERCENTAGE = 99;

    /// @notice The initial vote token balance granted to a user upon joining a debate.
    uint32 public constant INITIAL_TOKENS = 100;

    /// @notice The window after a debate finishes during which bounty claims are open; afterwards the
    /// creator may sweep the remainder.
    /// @dev A constant, not a creator knob: an unfloored creator-chosen window would allow sweeping
    /// before anyone can claim (see ADR-0009).
    uint48 public constant CLAIM_WINDOW = 7 days;

    /// @notice The maximum number of arguments per debate, the thesis included.
    /// @dev Bounds the atomic tally: the whole tree must be tallyable within one block's gas (asserted by the gas
    /// benchmark test). Depth needs no bound of its own - each tree level takes one locking window of
    /// finalization latency inside the editing phase - so the cap effectively governs breadth.
    uint16 public constant MAX_ARGUMENTS = 1024;

    /// @notice The fixed-point scale of an argument's own approval impact (full approval equals `type(uint32).max`).
    int64 internal constant _MAX_APPROVAL = int64(uint64(type(uint32).max));
}
