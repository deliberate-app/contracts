// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {CirclesIdentityRegistry, ICirclesHub} from "../src/adapters/CirclesIdentityRegistry.sol";
import {Deliberate} from "../src/Deliberate.sol";

/// @title DeployDeliberate
/// @notice Deploys Deliberate together with the Circles gate every deployment offers: a registry admitting any
/// Circles human, anchored on nothing. Who may join is chosen per debate, so Deliberate itself takes no
/// constructor arguments and cannot be upgraded.
contract DeployDeliberate is Script {
    /// @notice The Circles v2 Hub on Gnosis Chain, the only network the app targets.
    ICirclesHub public constant GNOSIS_CIRCLES_HUB = ICirclesHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    /// @notice Deploys against the Gnosis Circles Hub.
    /// @return deliberate The address of the deployed contract.
    /// @return circlesRegistry The address of the deployed any-Circles-human registry.
    function run() public returns (address deliberate, address circlesRegistry) {
        vm.startBroadcast();

        deliberate = address(new Deliberate());
        circlesRegistry =
            address(new CirclesIdentityRegistry({hub: GNOSIS_CIRCLES_HUB, anchor: address(0), requireHuman: true}));

        vm.stopBroadcast();
    }
}
