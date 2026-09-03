// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title Parameters
/// @author Michael Heuer
/// @notice A library collecting the protocol parameters governing every debate.
library Parameters {
    /// @notice The smallest vote token deposit an argument's creator may stake to seed the market reserves.
    /// @dev The creator picks the deposit; this floor keeps both market reserves non-empty across the seedable
    /// approval range (a degenerate zero reserve would freeze the constant-product market) and sets the minimum
    /// weight an argument carries into the tally. A multiple of 100, so that seeding at any whole percent splits
    /// the smallest permitted deposit exactly.
    uint32 internal constant _MIN_DEBATE_DEPOSIT = 1_000;

    /// @notice The highest market fee (in percent) a debate creator may set. Capping below 100 keeps
    /// every nonzero stake's net amount at least 1, so a stake can never degenerate into a pure fee
    /// transfer that moves no market.
    uint8 internal constant _MAX_FEE_PERCENTAGE = 99;

    /// @notice The initial vote token balance granted to a user upon joining a debate, in the protocol's
    /// smallest unit.
    /// @dev A participant's budget is one hundred tokens, held in hundredths so that the integer arithmetic
    /// downstream lands where the inputs say it should. Approvals and fees are whole percents, so a budget of
    /// exactly 100 units left both coarse: seeding the smallest permitted deposit was exact for five of the
    /// fifty seedable approvals and off by up to nine percentage points otherwise, and a 5% fee on any stake
    /// below a fifth of a budget rounded away to nothing. In hundredths every whole-percent seeding is exact
    /// and the fee survives stakes a hundred times smaller. Clients divide by one hundred to display it.
    uint32 public constant INITIAL_TOKENS = 10_000;

    /// @notice The window after a debate finishes during which bounty claims are open; afterwards the
    /// creator may sweep the remainder.
    /// @dev A constant, not a creator knob: a creator-chosen window with no floor could close before
    /// anyone had a chance to claim, letting the creator sweep the whole pool.
    uint48 public constant CLAIM_WINDOW = 7 days;

    /// @notice The maximum number of arguments per debate, the thesis included.
    /// @dev Bounds the atomic tally, which settles the whole tree in one transaction and is the only route to a
    /// finished debate - so a tree too large to tally is a tree whose deposits and bounty can never be released.
    /// The cap is therefore set against the tightest chain the protocol targets rather than the most generous:
    /// a full tree must settle in well under one Gnosis block (~17M gas). The cap governs breadth and depth
    /// alike, depth additionally costing one locking window of finalization latency per level.
    uint16 public constant MAX_ARGUMENTS = 512;

    /// @notice The longest content, in bytes of UTF-8, a thesis or argument may carry.
    /// @dev Content is calldata that the creation and alteration events publish; the contract keeps none of it
    /// and never reads it back, so the cap bounds what every reader carries and what a transaction can smuggle
    /// in, not storage. Bytes rather than characters, because the chain has no notion of the latter: 256 of
    /// them hold one claim stated sharply in any script.
    uint256 public constant MAX_CONTENT_LENGTH = 256;

    /// @notice The fixed-point scale of approvals and weighted ratings (the full scale equals `type(uint32).max`).
    int64 internal constant _MAX_APPROVAL = int64(uint64(type(uint32).max));
}
