// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ICirclesHub} from "../src/adapters/CirclesIdentityRegistry.sol";
import {IdentityRegistryFactory} from "../src/IdentityRegistryFactory.sol";

/// @title DeployIdentityRegistryFactory
/// @notice Deploys the identity registry factory. It also clones one registry from it: the registry that
/// admits every account which Circles has registered as a human.
contract DeployIdentityRegistryFactory is Script {
    /// @notice The Circles v2 Hub on Gnosis Chain, the only network the app targets.
    ICirclesHub public constant GNOSIS_CIRCLES_HUB = ICirclesHub(0xc12C1E50ABB450d6205Ea2C3Fa861b3B834d13e8);

    /// @notice Deploys the factory against the Gnosis Circles Hub, then clones one registry from it.
    /// @return factory The address of the deployed factory.
    /// @return circlesRegistry The address of the registry that admits every registered Circles human.
    function run() public returns (address factory, address circlesRegistry) {
        vm.startBroadcast();

        IdentityRegistryFactory deployed = new IdentityRegistryFactory(GNOSIS_CIRCLES_HUB);
        factory = address(deployed);
        circlesRegistry = deployed.createCirclesRegistry({anchor: address(0), requireHuman: true});

        vm.stopBroadcast();
    }
}
