// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {Phase} from "../src/libs/Phase.sol";
import {DebateGen} from "./libs/DebateGen.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract DebateGenExampleTest is Test {
    using DebateGen for Vm;

    uint48 internal constant _LOCKING_DURATION = 1 minutes;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate(new MockIdentityRegistry());
    }

    function test_everyArgumentsContentIsItsOwnId() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);

        uint16 pro = vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);
        uint16 con = vm.addCon(debate, _BOB, DebateGen.ROOT, 60);

        assertEq(vm.argumentOf(debate, pro).contentURI, bytes32(uint256(pro)));
        assertEq(vm.argumentOf(debate, con).contentURI, bytes32(uint256(con)));
    }

    function test_talliesASupportingArgumentToApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);

        vm.warpToTallying(debate);
        vm.tally(debate);

        assertEq(uint256(vm.phaseOf(debate)), uint256(Phase.Status.Finished));
        assertTrue(vm.outcome(debate));
        assertGt(vm.descendantsImpact(debate, DebateGen.ROOT), 0);
    }

    function test_stakingConLowersTheApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50); // reserves 5/5 at the min deposit

        vm.warpToRating(debate);
        vm.stakeCon(debate, _BOB, argumentId, 20);

        assertLt(vm.approvalBps(debate, argumentId), 5000); // pushed below neutral
        assertEq(vm.tokensOf(debate, _BOB), 80); // 100 granted on join, 20 staked
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
