// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployCirclesIdentityRegistry} from "../script/DeployCirclesIdentityRegistry.s.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MockCirclesHub} from "./mocks/MockCirclesHub.m.sol";

contract DeployCirclesIdentityRegistryTest is Test {
    DeployCirclesIdentityRegistry internal _script;
    MockCirclesHub internal _hub;

    function setUp() public {
        _script = new DeployCirclesIdentityRegistry();
        // The mock stands in for the Circles Hub at its Gnosis address, so the script runs exactly as it would there.
        _hub = MockCirclesHub(address(_script.GNOSIS_CIRCLES_HUB()));
        vm.etch(address(_hub), type(MockCirclesHub).runtimeCode);
    }

    function test_run_deploysAnAnyCirclesHumanGateOnTheGnosisHub() public {
        address circlesRegistry = _script.run();
        address human = makeAddr("human");
        _hub.setHuman(human, true);

        assertTrue(IIdentityRegistry(circlesRegistry).isRegistered(human));
        assertFalse(IIdentityRegistry(circlesRegistry).isRegistered(makeAddr("stranger")));
    }
}
