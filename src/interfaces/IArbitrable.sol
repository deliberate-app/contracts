// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IArbitrator} from "./IArbitrator.sol";

// From the Aragon protocol IArbitrable.sol (packages/evm/contracts/arbitration).

/// @title IArbitrable
/// @author Michael Heuer
/// @notice The interface identifying an arbitrable instance ruled by an `IArbitrator`.
/// @dev Following this interface is optional; it allows the arbitrator to identify a set of instances.
abstract contract IArbitrable {
    /// @notice Emitted when an arbitrable instance's dispute is ruled by an arbitrator.
    /// @param arbitrator The arbitrator instance ruling the dispute.
    /// @param disputeId The identification number of the dispute being ruled by the arbitrator.
    /// @param ruling The ruling given by the arbitrator.
    event Ruled(IArbitrator indexed arbitrator, uint256 indexed disputeId, uint256 ruling);
}
