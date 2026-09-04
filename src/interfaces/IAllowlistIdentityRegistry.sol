// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IIdentityRegistry} from "./IIdentityRegistry.sol";

/// @title IAllowlistIdentityRegistry
/// @author Michael Heuer
/// @notice The interface of an identity registry whose membership one owner maintains directly.
interface IAllowlistIdentityRegistry is IIdentityRegistry {
    /// @notice Emitted when an account's membership changes.
    /// @param account The account whose membership changed.
    /// @param member Whether the account is now a member.
    event MembershipSet(address indexed account, bool member);

    /// @notice Sets the membership of several accounts at once.
    /// @param accounts The accounts to set membership for; repeated accounts settle on the last write.
    /// @param member Whether the accounts become members.
    function setMembership(address[] calldata accounts, bool member) external;
}
