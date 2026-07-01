// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

// From the Aragon protocol IArbitrator.sol (packages/evm/contracts/arbitration).

/// @title IArbitrator
/// @author Michael Heuer
/// @notice The interface of an arbitrator creating and ruling disputes over arbitrable instances.
interface IArbitrator {
    /// @notice Creates a dispute over the arbitrable sender with a number of possible rulings.
    /// @param possibleRulings Number of possible rulings allowed for the dispute.
    /// @param metadata Optional metadata providing additional information on the dispute to be created.
    /// @return disputeId The dispute identification number.
    function createDispute(uint256 possibleRulings, bytes calldata metadata) external returns (uint256 disputeId);

    /// @notice Submits evidence for a dispute.
    /// @param disputeId The ID of the dispute in the protocol.
    /// @param submitter The address of the account submitting the evidence.
    /// @param evidence The data submitted for the evidence related to the dispute.
    function submitEvidence(uint256 disputeId, address submitter, bytes calldata evidence) external;

    /// @notice Closes the evidence period of a dispute.
    /// @param disputeId The identification number of the dispute to close the evidence period of.
    function closeEvidencePeriod(uint256 disputeId) external;

    /// @notice Rules a dispute if ready.
    /// @param disputeId The identification number of the dispute to be ruled.
    /// @return subject The subject associated to the dispute.
    /// @return ruling The ruling number computed for the given dispute.
    function rule(uint256 disputeId) external returns (address subject, uint256 ruling);

    /// @notice Tells the dispute fees information to create a dispute.
    /// @return recipient The address the corresponding dispute fees must be transferred to.
    /// @return feeToken The ERC20 token used for the fees.
    /// @return feeAmount The total amount of fees that must be allowed to the recipient.
    function getDisputeFees() external view returns (address recipient, ERC20 feeToken, uint256 feeAmount);

    /// @notice Tells the payments recipient address.
    /// @return recipient The address of the payments recipient module.
    function getPaymentsRecipient() external view returns (address recipient);
}
