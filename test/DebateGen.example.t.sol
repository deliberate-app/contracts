// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {Phase} from "../src/libs/Phase.sol";
import {DebateGen} from "./libs/DebateGen.sol";
import {MockProofOfHumanity} from "./mocks/MockProofOfHumanity.m.sol";

contract DebateGenExampleTest is Test {
    using DebateGen for Vm;

    uint48 internal constant _TIME_UNIT = 1 minutes;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    ArborVote internal _arborVote;

    function setUp() public {
        _arborVote = new ArborVote(new MockProofOfHumanity());
    }

    function test_everyArgumentsContentIsItsOwnId() public {
        DebateGen.Debate memory debate = vm.createDebate(_arborVote, _ALICE, _TIME_UNIT);

        uint16 pro = vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);
        uint16 con = vm.addCon(debate, _BOB, DebateGen.ROOT, 60);

        assertEq(vm.argumentOf(debate, pro).contentURI, bytes32(uint256(pro)));
        assertEq(vm.argumentOf(debate, con).contentURI, bytes32(uint256(con)));
    }

    function test_talliesASupportingArgumentToApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_arborVote, _ALICE, _TIME_UNIT);
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);

        vm.warpToTallying(debate);
        vm.tally(debate);

        assertEq(uint256(vm.phaseOf(debate)), uint256(Phase.Status.Finished));
        assertTrue(vm.outcome(debate));
        assertGt(vm.descendantsImpact(debate, DebateGen.ROOT), 0);
    }

    function test_stakingConLowersTheApproval() public {
        DebateGen.Debate memory debate = vm.createDebate(_arborVote, _ALICE, _TIME_UNIT);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50); // reserves 5/5 at the min deposit

        vm.warpToRating(debate);
        vm.stakeCon(debate, _BOB, argumentId, 20);

        assertLt(vm.approvalBps(debate, argumentId), 5000); // pushed below neutral
        assertEq(vm.tokensOf(debate, _BOB), 80); // 100 granted on join, 20 staked
    }

    function test_buildsADeeperTreeAcrossFinalizationWindows() public {
        DebateGen.Debate memory debate = vm.createDebate(_arborVote, _ALICE, _TIME_UNIT);

        uint16 a1 = vm.addPro(debate, _ALICE, DebateGen.ROOT, 80);
        vm.warpUnits(debate, 1); // a1 finalizes, so it can now be a parent
        uint16 a2 = vm.addCon(debate, _BOB, a1, 70);
        vm.warpUnits(debate, 1); // a2 finalizes
        uint16 a3 = vm.addPro(debate, _CAROL, a2, 65);

        assertEq(vm.argumentOf(debate, a2).parentArgumentId, a1);
        assertEq(vm.argumentOf(debate, a3).parentArgumentId, a2);
    }
}
