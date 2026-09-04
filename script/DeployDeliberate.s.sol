// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {Deliberate} from "../src/Deliberate.sol";

/// @title DeployDeliberate
/// @notice Deploys Deliberate. Who may join is chosen per debate, so it takes no constructor arguments and
/// cannot be upgraded - and the identity registries a creator may point at are deployed separately, on
/// their own schedule (`DeployCirclesIdentityRegistry` for the Circles gate a deployment offers by
/// default).
contract DeployDeliberate is Script {
    /// @notice Deploys the protocol.
    /// @return deliberate The address of the deployed contract.
    function run() public returns (address deliberate) {
        vm.startBroadcast();

        deliberate = address(new Deliberate());

        vm.stopBroadcast();
    }
}
