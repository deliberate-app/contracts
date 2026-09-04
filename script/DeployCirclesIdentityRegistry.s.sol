// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {CirclesIdentityRegistry, ICirclesHub} from "../src/adapters/CirclesIdentityRegistry.sol";

/// @title DeployCirclesIdentityRegistry
/// @notice Deploys the Circles gate a deployment offers by default: a registry admitting any Circles human,
/// anchored on nothing. It is deployed on its own because it is not part of the protocol - who may join is
/// chosen per debate, from any address implementing `IIdentityRegistry`, so this adapter is one option
/// among several and outlives any single Deliberate deployment. A creator wanting a curated gate deploys
/// the same adapter with an anchor instead, or points at a registry of their own.
contract DeployCirclesIdentityRegistry is Script {
    /// @notice The Circles v2 Hub on Gnosis Chain, the only network the app targets.
    ICirclesHub public constant GNOSIS_CIRCLES_HUB = ICirclesHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    /// @notice Deploys the any-Circles-human registry against the Gnosis Circles Hub.
    /// @return circlesRegistry The address of the deployed registry.
    function run() public returns (address circlesRegistry) {
        vm.startBroadcast();

        circlesRegistry =
            address(new CirclesIdentityRegistry({hub: GNOSIS_CIRCLES_HUB, anchor: address(0), requireHuman: true}));

        vm.stopBroadcast();
    }
}
