// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {IDeliberate} from "../src/interfaces/IDeliberate.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {DebateGen} from "./libs/DebateGen.sol";

contract DebateGenExampleTest is Test {
    using DebateGen for Vm;

    uint48 internal constant _LOCKING_DURATION = 1 minutes;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate();
    }

    function test_everyArgumentsContentIsItsOwnId() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);

        // Content is published, never stored: the creation event is the one place it can be read back.
        vm.recordLogs();
        uint16 pro = vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);
        uint16 con = vm.addCon(debate, _BOB, DebateGen.ROOT, 60);

        string[] memory contents = _createdContents(vm.getRecordedLogs());
        assertEq(contents.length, 2);
        assertEq(contents[0], vm.toString(uint256(pro)));
        assertEq(contents[1], vm.toString(uint256(con)));
    }

    // The content of every `ArgumentCreated` among the logs, in order.
    function _createdContents(Vm.Log[] memory logs) internal pure returns (string[] memory contents) {
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IDeliberate.ArgumentCreated.selector) {
                count++;
            }
        }
        contents = new string[](count);
        uint256 next = 0;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == IDeliberate.ArgumentCreated.selector) {
                (,, string memory content,,,) =
                    abi.decode(logs[i].data, (address, bool, string, uint32, uint32, uint48));
                contents[next++] = content;
            }
        }
    }

    function test_talliesASupportingArgumentToApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);

        vm.warpToTallying(debate);
        vm.tally(debate);

        assertEq(uint256(vm.phaseOf(debate)), uint256(Phase.Status.Finished));
        assertTrue(vm.outcome(debate));
        assertGt(vm.descendantsAggregate(debate, DebateGen.ROOT), 0);
    }

    function test_stakingConLowersTheApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50); // reserves (500, 500) at the minimum deposit

        vm.warpToRating(debate);
        vm.stakeCon(debate, _BOB, argumentId, 2000);

        assertLt(vm.approvalBps(debate, argumentId), 5000); // pushed below neutral
        assertEq(vm.tokensOf(debate, _BOB), Parameters.INITIAL_TOKENS - 2000);
    }

    function test_buildsADeeperTreeAcrossFinalizationWindows() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);

        uint16 a1 = vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);
        vm.warpWindows(debate, 1); // a1 finalizes, so it can now be a parent
        uint16 a2 = vm.addCon(debate, _BOB, a1, 70);
        vm.warpWindows(debate, 1); // a2 finalizes
        uint16 a3 = vm.addPro(debate, _CAROL, a2, 65);

        assertEq(vm.argumentOf(debate, a2).parentArgumentId, a1);
        assertEq(vm.argumentOf(debate, a3).parentArgumentId, a2);
    }
}
