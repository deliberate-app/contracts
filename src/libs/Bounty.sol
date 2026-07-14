// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";

/// @title Bounty
/// @author Michael Heuer
/// @notice A library defining the bounty type: the ERC-20 prize a debate's creator attaches at creation,
/// claimable by net winners of the vote-token game once the debate is finished.
library Bounty {
    /// @notice The data associated with a debate's bounty.
    /// @param token The ERC-20 the bounty is denominated in; the zero address means the debate has no bounty.
    /// @param swept Whether the creator has swept the unclaimed remainder after the claim window.
    /// @param pool The total amount funded (creation deposit plus top-ups), measured as received.
    /// @param claimed The total amount paid out to claimants so far.
    struct Data {
        IERC20 token; //   ┐  20
        bool swept; //     ┘ + 1 = 21
        uint256 pool; //   ]  32
        uint256 claimed; // ] 32
    }
}
