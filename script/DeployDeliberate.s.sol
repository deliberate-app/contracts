// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {Deliberate} from "../src/Deliberate.sol";

/// @title DeployDeliberate
/// @notice A script deploying the Deliberate contract, which takes no constructor arguments and cannot be
/// upgraded. Who may join is chosen per debate at creation, not per deployment, so one deployment serves
/// open debates, creator-curated groups and Circles-gated debates alike.
contract DeployDeliberate is Script {
    /// @notice Deploys Deliberate.
    /// @return deliberate The address of the deployed contract.
    function run() public returns (address deliberate) {
        vm.startBroadcast();

        deliberate = address(new Deliberate());

        vm.stopBroadcast();
    }
}
