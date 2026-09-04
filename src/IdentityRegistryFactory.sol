// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";

import {AllowlistIdentityRegistry} from "./adapters/AllowlistIdentityRegistry.sol";
import {CirclesIdentityRegistry, ICirclesHub} from "./adapters/CirclesIdentityRegistry.sol";
import {IIdentityRegistryFactory} from "./interfaces/IIdentityRegistryFactory.sol";

/// @title IdentityRegistryFactory
/// @author Michael Heuer
/// @notice Deploys identity registries as EIP-1167 minimal proxies. A registry admits the accounts on a
/// list that its owner keeps, or the accounts that the Circles Hub of this factory reports.
contract IdentityRegistryFactory is IIdentityRegistryFactory {
    /// @notice The allowlist implementation every allowlist clone delegates to.
    address internal immutable _ALLOWLIST_IMPLEMENTATION;

    /// @notice The Circles implementation every Circles clone delegates to, bound to one Hub.
    address internal immutable _CIRCLES_IMPLEMENTATION;

    /// @notice Deploys the factory and one implementation for each kind of registry it creates.
    /// @param hub The Circles v2 Hub that every Circles registry from this factory reads. A clone
    /// delegatecalls the implementation, so the Hub stays in code and the clone holds only its own
    /// anchor and personhood setting.
    constructor(ICirclesHub hub) {
        _ALLOWLIST_IMPLEMENTATION = address(new AllowlistIdentityRegistry());
        _CIRCLES_IMPLEMENTATION = address(new CirclesIdentityRegistry(hub));
    }

    /// @inheritdoc IIdentityRegistryFactory
    function createAllowlistRegistry(address owner) external override returns (address registry) {
        registry = Clones.clone(_ALLOWLIST_IMPLEMENTATION);
        AllowlistIdentityRegistry(registry).initialize(owner);

        emit AllowlistRegistryCreated({registry: registry, owner: owner});
    }

    /// @inheritdoc IIdentityRegistryFactory
    function createCirclesRegistry(address anchor, bool requireHuman) external override returns (address registry) {
        registry = Clones.clone(_CIRCLES_IMPLEMENTATION);
        CirclesIdentityRegistry(registry).initialize({trustAnchor: anchor, humanRequired: requireHuman});

        emit CirclesRegistryCreated({registry: registry, anchor: anchor, requireHuman: requireHuman});
    }

    /// @inheritdoc IIdentityRegistryFactory
    function allowlistImplementation() external view override returns (address implementation) {
        implementation = _ALLOWLIST_IMPLEMENTATION;
    }

    /// @inheritdoc IIdentityRegistryFactory
    function circlesImplementation() external view override returns (address implementation) {
        implementation = _CIRCLES_IMPLEMENTATION;
    }
}
