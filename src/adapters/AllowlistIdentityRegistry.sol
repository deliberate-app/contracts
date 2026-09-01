// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin-contracts-5.6.1/access/Ownable.sol";

import {IAllowlistIdentityRegistry} from "../interfaces/IAllowlistIdentityRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title AllowlistIdentityRegistry
/// @author Michael Heuer
/// @notice An identity registry whose membership its owner maintains directly - the group a creator curates
/// themselves, for communities that keep no membership anywhere a contract could already read.
///
/// One registry serves any number of debates: a creator deploys it once, curates it as the group changes,
/// and passes its address to every debate that group should decide. Membership is read at the moment of
/// joining, so removing an account bars it from joining afterwards without disturbing debates it already
/// joined - vote tokens are granted once and settle inside the debate that granted them.
///
/// The owner is trusted completely, which is the point: this is a stated, legible authority over who
/// participates, and it makes no claim to sybil resistance beyond the owner's own diligence.
contract AllowlistIdentityRegistry is IAllowlistIdentityRegistry, Ownable {
    /// @notice The members by account.
    mapping(address account => bool member) internal _members;

    /// @notice Deploys the registry under an owner who maintains its membership.
    /// @param initialOwner The account receiving ownership, and with it sole authority over who may join
    /// every debate this registry gates.
    constructor(address initialOwner) Ownable(initialOwner) {}

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
