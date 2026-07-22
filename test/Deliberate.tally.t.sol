// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {DebateGen} from "./libs/DebateGen.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

// The stake-weighted tally (ADR-0011): an argument's rating blends its own approval with its
// descendants' aggregate by the stake behind each, and a child speaks at its parent with its whole
// subtree's stake. Exact fixed-point expectations - a changed rounding or weighting fails loudly.
contract DeliberateTallyTest is Test {
    using DebateGen for Vm;

    // Expected values are in the tally's fixed point, where full approval is
    // `Parameters._MAX_APPROVAL` = type(uint32).max = 4294967295 ("MAX" in the comments).
    uint48 internal constant _LOCKING_DURATION = 1 minutes;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate(new MockIdentityRegistry());
    }

    function test_aLoneArgumentSwaysTheThesisWithItsFullApproval() public {
        // The production scenario that motivated the change, at the 1% fee: a lone pro argument
        // rated up to 104/105 ~ 99% approval. Under the old fixed 50:50 blend its empty
        // descendants slot halved the sway to ~50%; now a leaf keeps its full own approval.
        DebateGen.Debate memory debate = vm.createDebateWithFee(_deliberate, _ALICE, _LOCKING_DURATION, 1);
        uint16 argumentId = vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 50,
            deposit: 10
        });
        vm.warpToRating(debate);
        vm.stakePro(debate, _BOB, argumentId, 100); // fee 1 -> net 99: reserves (1, 104), votes 109

        vm.warpToTallying(debate);
        vm.tally(debate);

        // floor(MAX * 104/105) = 4254062844 ~ 99.0% of full approval, folded with full weight.
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 4254062844);
        assertTrue(vm.outcome(debate));
    }

    function test_aCheapChildCorrectsInProportionToItsStake() public {
        // Burial repriced: under the fixed 50:50 blend a minimum-deposit con child owned half of
        // any parent's blend outright; now its pull is its stake share. A 10-token con child at
        // 90% approval against a 105-token parent market moves the blend from ~99% to ~83%,
        // not to near-zero.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 parent = vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 50,
            deposit: 10
        });
        vm.warpWindows(debate, 1); // the parent finalizes, so it can be replied to
        uint16 child = vm.addArgument({
            debate: debate, author: _CAROL, parentId: parent, isSupporting: false, initialApproval: 90, deposit: 10
        });
        vm.warpToRating(debate);
        vm.stakePro(debate, _BOB, parent, 100); // fee 5 -> net 95: reserves (1, 100), votes 105

        vm.warpToTallying(debate);
        vm.tally(debate);

        // Child (leaf): floor(MAX * 9/10) = 3865470565, subtree stake 10.
        // Parent blend: (floor(MAX * 100/101) * 105 - 3865470565 * 10) / 115 = 3546537350 ~ 82.6%.
        assertEq(vm.argumentOf(debate, child).subtreeVotes, 10);
        assertEq(vm.argumentOf(debate, parent).subtreeVotes, 115);
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 3546537350);
        assertTrue(vm.outcome(debate));
    }

    function test_siblingsWeighWithTheirWholeSubtreesStake() public {
        // Two pro siblings with equal own markets (10 each): A a plain leaf at 90%, B seeded
        // neutral but carrying a 40-token sub-debate at 90%. B's subtree (50) outweighs A (10)
        // at the thesis - under own-votes weighting they would count equally.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 90,
            deposit: 10
        });
        uint16 b = vm.addArgument({
            debate: debate, author: _BOB, parentId: DebateGen.ROOT, isSupporting: true, initialApproval: 50, deposit: 10
        });
        vm.warpWindows(debate, 1);
        vm.addArgument({
            debate: debate, author: _CAROL, parentId: b, isSupporting: true, initialApproval: 90, deposit: 40
        });

        vm.warpToTallying(debate);
        vm.tally(debate);

        // A: floor(MAX * 9/10) = 3865470565, subtree 10. C: floor(MAX * 36/40) = 3865470565, subtree 40.
        // B blend: (floor(MAX/2) * 10 + 3865470565 * 40) / 50 = 3521873181, subtree 50.
        // Thesis: (3865470565 * 10 + 3521873181 * 50) / 60 = 3579139411 - the subtree-weighted mean,
        // not the own-votes mean (3693671873).
        assertEq(vm.argumentOf(debate, b).subtreeVotes, 50);
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 3579139411);

        // The thesis' accumulated weight is the whole debate's stake - every market counted once.
        assertEq(vm.argumentOf(debate, DebateGen.ROOT).subtreeVotes, vm.totalVotesOf(debate));
    }
}
