// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";

import {IAllowlistIdentityRegistry} from "../interfaces/IAllowlistIdentityRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title AllowlistIdentityRegistry
/// @author Michael Heuer
/// @notice An identity registry that admits the accounts on a list. Its owner keeps the list, and one
/// registry can serve any number of debates. The factory clones it, so `initialize` sets the owner.
contract AllowlistIdentityRegistry is IAllowlistIdentityRegistry, Initializable, OwnableUpgradeable {
    /// @notice The members by account.
    mapping(address account => bool member) internal _members;

    /// @notice Leaves the implementation uninitialized. It exists to be cloned, and an owner must not be
    /// able to take it over.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IAllowlistIdentityRegistry
    function initialize(address initialOwner) external override initializer {
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc IAllowlistIdentityRegistry
    function setMembership(address[] calldata accounts, bool member) external override onlyOwner {
        uint256 arrayLength = accounts.length;
        for (uint256 i = 0; i < arrayLength; i++) {
            _members[accounts[i]] = member;

            emit MembershipSet({account: accounts[i], member: member});
        }
    }

    /// @inheritdoc IIdentityRegistry
    function isRegistered(address account) external view override returns (bool registered) {
        registered = _members[account];
    }
}
