// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployDeliberate} from "../script/DeployDeliberate.s.sol";
import {Deliberate} from "../src/Deliberate.sol";

contract DeployDeliberateTest is Test {
    DeployDeliberate internal _script;

    function setUp() public {
        _script = new DeployDeliberate();
    }

    function test_run_deploysDeliberate() public {
        address deliberate = _script.run();

        assertEq(Deliberate(deliberate).debatesCount(), 0);
    }
}
