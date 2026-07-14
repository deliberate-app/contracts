// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MockIdentityRegistry} from "../test/mocks/MockIdentityRegistry.m.sol";

/// @title DeployArborVote
/// @notice A script deploying the ArborVote contract (not upgradeable, see ADR-0006).
contract DeployArborVote is Script {
    /// @notice Deploys ArborVote against an existing identity registry (or an adapter to one).
    function run(address identityRegistry) public returns (address arborVote) {
        vm.startBroadcast();

        arborVote = address(new ArborVote(IIdentityRegistry(identityRegistry)));

        vm.stopBroadcast();
    }

    /// @notice Deploys a MockIdentityRegistry (everyone counts as registered) alongside
    /// ArborVote - for test networks without a real identity registry.
    function runWithMockRegistry() public returns (address arborVote, address identityRegistry) {
        vm.startBroadcast();

        identityRegistry = address(new MockIdentityRegistry());
        arborVote = address(new ArborVote(IIdentityRegistry(identityRegistry)));

        vm.stopBroadcast();
    }
}
