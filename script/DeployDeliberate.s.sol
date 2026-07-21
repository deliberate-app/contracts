// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MockIdentityRegistry} from "../test/mocks/MockIdentityRegistry.m.sol";

/// @title DeployDeliberate
/// @notice A script deploying the Deliberate contract (not upgradeable, see ADR-0006).
contract DeployDeliberate is Script {
    /// @notice Deploys Deliberate against an existing identity registry (or an adapter to one).
    function run(address identityRegistry) public returns (address deliberate) {
        vm.startBroadcast();

        deliberate = address(new Deliberate(IIdentityRegistry(identityRegistry)));

        vm.stopBroadcast();
    }

    /// @notice Deploys a MockIdentityRegistry (everyone counts as registered) alongside
    /// Deliberate - for test networks without a real identity registry.
    function runWithMockRegistry() public returns (address deliberate, address identityRegistry) {
        vm.startBroadcast();

        identityRegistry = address(new MockIdentityRegistry());
        deliberate = address(new Deliberate(IIdentityRegistry(identityRegistry)));

        vm.stopBroadcast();
    }
}
