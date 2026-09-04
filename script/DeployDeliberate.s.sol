// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {Deliberate} from "../src/Deliberate.sol";

/// @title DeployDeliberate
/// @notice Deploys Deliberate. It takes no constructor arguments. Identity registries are not part of the
/// protocol; `DeployIdentityRegistryFactory` deploys them.
contract DeployDeliberate is Script {
    /// @notice Deploys the protocol.
    /// @return deliberate The address of the deployed contract.
    function run() public returns (address deliberate) {
        vm.startBroadcast();

        deliberate = address(new Deliberate());

        vm.stopBroadcast();
    }
}
