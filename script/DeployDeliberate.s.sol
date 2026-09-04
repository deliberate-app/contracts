// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {Deliberate} from "../src/Deliberate.sol";

/// @title DeployDeliberate
/// @notice Deploys Deliberate. Identity registries are not part of the protocol, so
/// `DeployIdentityRegistryFactory` deploys them separately.
contract DeployDeliberate is Script {
    /// @return deliberate The address of the deployed contract.
    function run() public returns (address deliberate) {
        vm.startBroadcast();

        deliberate = address(new Deliberate());

        vm.stopBroadcast();
    }
}
