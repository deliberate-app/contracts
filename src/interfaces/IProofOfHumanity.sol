// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// https://etherscan.io/address/0x1dAD862095d40d43c2109370121cf087632874dB#code

/// @title IProofOfHumanity
/// @author Michael Heuer
/// @notice The interface of the Proof of Humanity registry.
interface IProofOfHumanity {
    /// @notice Returns whether a submission is registered and not expired.
    /// @param submissionID The address of the submission.
    /// @return registered Whether the submission is registered or not.
    function isRegistered(address submissionID) external view returns (bool registered);

    /// @notice Returns the number of submissions irrespective of their status.
    /// @return count The number of submissions.
    function submissionCounter() external view returns (uint256 count);
}
