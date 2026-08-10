// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {DebateGen} from "./libs/DebateGen.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

// The stake-weighted tally (ADR-0011) on the centered scale (ADR-0012): an argument's rating
// blends its own centered approval - zero at the market's undecided price - with its descendants'
// aggregate by the stake behind each; a child speaks at its parent with its whole subtree's stake,
// and a refuted child (negative rating) sways nothing while keeping its weight. Exact fixed-point
// expectations - a changed rounding, weighting, or clamp fails loudly.
contract DeliberateTallyTest is Test {
    using DebateGen for Vm;

    // Expected values are in the tally's fixed point, where full conviction is
    // `Parameters._MAX_APPROVAL` = type(uint32).max = 4294967295 ("MAX" in the comments); an
    // argument's centered own approval is MAX * (con - pro) / (pro + con).
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

        // Centered: floor(MAX * (104-1)/105) = 4213158394 ~ 98.1% conviction, folded with full weight.
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 4213158394);
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

        // Child (leaf), centered: floor(MAX * (9-1)/10) = 3435973836, subtree stake 10.
        // Parent blend: (floor(MAX * (100-1)/101) * 105 - 3435973836 * 10) / 115 = 3545058239 ~ 82.5%.
        assertEq(vm.argumentOf(debate, child).subtreeVotes, 10);
        assertEq(vm.argumentOf(debate, parent).subtreeVotes, 115);
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 3545058239);
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

        // A: floor(MAX * (9-1)/10) = 3435973836, subtree 10. C: floor(MAX * (36-4)/40) = 3435973836,
        // subtree 40. B, seeded neutral, contributes zero of its own: blend
        // (0 * 10 + 3435973836 * 40) / 50 = 2748779068, subtree 50.
        // Thesis: (3435973836 * 10 + 2748779068 * 50) / 60 = 2863311529 - the subtree-weighted mean,
        // not the own-votes mean (3092376452).
        assertEq(vm.argumentOf(debate, b).subtreeVotes, 50);
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 2863311529);

        // The thesis' accumulated weight is the whole debate's stake - every market counted once.
        assertEq(vm.argumentOf(debate, DebateGen.ROOT).subtreeVotes, vm.totalVotesOf(debate));
    }

    function test_aRefutedArgumentSwaysNothingButKeepsItsWeight() public {
        // The live scenario that motivated the clamp (debate 4, argument 7): an attack demolished
        // by its own counter-arguments. Without the clamp its negative rating, negated by the con
        // stance, CONFIRMED the thesis it attacked - planting a weak attack and refuting it paid
        // better than supporting the thesis directly. With it, refuted means silenced: the attack
        // folds at zero strength but full subtree weight, so it dampens its neighborhood instead
        // of switching sides.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 90,
            deposit: 10
        });
        uint16 attack = vm.addArgument({
            debate: debate,
            author: _BOB,
            parentId: DebateGen.ROOT,
            isSupporting: false,
            initialApproval: 50,
            deposit: 10
        });
        vm.warpWindows(debate, 1);
        vm.addArgument({
            debate: debate, author: _CAROL, parentId: attack, isSupporting: false, initialApproval: 90, deposit: 30
        });

        vm.warpToTallying(debate);
        vm.tally(debate);

        // The attack's rating: (0 * 10 - 3435973836 * 30) / 40 = -2576980377, refuted - clamped
        // to zero at the fold. The supporter: floor(MAX * (9-1)/10) = 3435973836, subtree 10.
        // Thesis: (3435973836 * 10 + 0 * 40) / 50 = 687194767 - diluted by the refuted subtree's
        // kept weight, not raised by it (unclamped it would read (34359738360 + 2576980377 * 40)
        // / 50, the attack aiding the thesis), and not the supporter's lone voice either.
        assertEq(vm.argumentOf(debate, attack).subtreeVotes, 40);
        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 687194767);
        assertTrue(vm.outcome(debate));
        assertEq(vm.argumentOf(debate, DebateGen.ROOT).subtreeVotes, vm.totalVotesOf(debate));
    }

    function test_aNeutralMarketSwaysNothingAndSilenceObjects() public {
        // The seed floor is the neutral point: a lone argument left at its 50% seed carries no
        // conviction either way, so the thesis nets exactly zero - and zero does not confirm.
        // Silence never approves a thesis; only positive net endorsement does.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 50,
            deposit: 10
        });

        vm.warpToTallying(debate);
        vm.tally(debate);

        assertEq(vm.descendantsImpact(debate, DebateGen.ROOT), 0);
        assertFalse(vm.outcome(debate));
    }
}
