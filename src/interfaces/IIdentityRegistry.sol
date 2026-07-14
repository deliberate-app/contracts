// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/// @title IIdentityRegistry
/// @author Michael Heuer
/// @notice The minimal interface of an on-chain identity registry: an externally operated service links
/// accounts to verified identities and answers membership queries.
interface IIdentityRegistry {
    /// @notice Returns whether an account belongs to a registered, currently valid identity.
    /// @param account The account to check.
    /// @return registered Whether the account is registered.
    function isRegistered(address account) external view returns (bool registered);
}
