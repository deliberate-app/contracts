// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @title IIdentityRegistryFactory
/// @author Michael Heuer
/// @notice The interface of the factory that deploys identity registries as minimal proxies.
interface IIdentityRegistryFactory {
    /// @notice Emitted when an allowlist registry is created.
    /// @param registry The address of the new registry.
    /// @param owner The account that owns the registry and keeps its list.
    event AllowlistRegistryCreated(address indexed registry, address indexed owner);

    /// @notice Emitted when a Circles registry is created.
    /// @param registry The address of the new registry.
    /// @param anchor The avatar whose trust admits an account. The zero address admits every registered
    /// Circles human instead.
    /// @param requireHuman Whether an admitted account must also be a registered human.
    event CirclesRegistryCreated(address indexed registry, address indexed anchor, bool requireHuman);

    /// @notice Creates an allowlist registry owned by an account that curates its membership.
    /// @param owner The account receiving ownership of the new registry.
    /// @return registry The address of the new registry.
    function createAllowlistRegistry(address owner) external returns (address registry);

    /// @notice Creates a registry that reads the Circles Hub of this factory.
    /// @param anchor The avatar whose trust admits an account. The zero address admits every registered
    /// Circles human instead.
    /// @param requireHuman Whether an admitted account must also be a registered human.
    /// @return registry The address of the new registry.
    function createCirclesRegistry(address anchor, bool requireHuman) external returns (address registry);

    /// @notice Returns the implementation every allowlist registry from this factory delegates to.
    /// @return implementation The allowlist implementation.
    function allowlistImplementation() external view returns (address implementation);

    /// @notice Returns the implementation every Circles registry from this factory delegates to.
    /// @return implementation The Circles implementation.
    function circlesImplementation() external view returns (address implementation);
}
