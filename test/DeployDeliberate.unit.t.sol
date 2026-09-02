// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployDeliberate} from "../script/DeployDeliberate.s.sol";
import {Deliberate} from "../src/Deliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MockCirclesHub} from "./mocks/MockCirclesHub.m.sol";

contract DeployDeliberateTest is Test {
    DeployDeliberate internal _script;
    MockCirclesHub internal _hub;

    function setUp() public {
        _script = new DeployDeliberate();
        // The mock stands in for the Circles Hub at its Gnosis address, so the script runs exactly as it would there.
        _hub = MockCirclesHub(address(_script.GNOSIS_CIRCLES_HUB()));
        vm.etch(address(_hub), type(MockCirclesHub).runtimeCode);
    }

    function test_run_deploysDeliberate() public {
        (address deliberate,) = _script.run();

        assertEq(Deliberate(deliberate).debatesCount(), 0);
    }

    function test_run_deploysAnAnyCirclesHumanGateOnTheGnosisHub() public {
        (, address circlesRegistry) = _script.run();
        address human = makeAddr("human");
        _hub.setHuman(human, true);

        assertTrue(IIdentityRegistry(circlesRegistry).isRegistered(human));
        assertFalse(IIdentityRegistry(circlesRegistry).isRegistered(makeAddr("stranger")));
    }
}
