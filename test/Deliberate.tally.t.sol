// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {DebateGen} from "./libs/DebateGen.sol";

// The stake-weighted tally on the centered scale, reading time-weighted inputs: an argument's rating
// blends its own centered approval - zero at the market's undecided price, each price counting for the
// seconds it stood in the rating window - with its descendants' aggregate by the time-weighted stake
// behind each; a child speaks at its parent with its whole subtree's stake, and a refuted child
// (negative rating) sways nothing while keeping its weight. Exact fixed-point expectations - a changed
// rounding, weighting, clamp, or accrual fails loudly. Stakes land in the rating window's first second
// (`warpToRating`), so a seeded price stands 1 of the 180-second window and the corrected price the
// remaining 179.
contract DeliberateTallyTest is Test {
    using DebateGen for Vm;

    // Expected values are in the tally's fixed point, where full conviction is
    // `Parameters._MAX_APPROVAL` = type(uint32).max = 4294967295 ("MAX" in the comments); an
    // argument's centered own approval is MAX * (con - pro) / (pro + con). Stakes and reserves are in the
    // contract's unit, a hundredth of a vote token.
    uint48 internal constant _LOCKING_DURATION = 1 minutes;

    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate();
    }

    function test_aLoneArgumentSwaysTheThesisWithItsFullApproval() public {
        // The production scenario that motivated the change, at the 1% fee: a lone pro argument
        // rated up to 104/105 ~ 99% approval. Under the old fixed 50:50 blend its empty
        // descendants slot halved the sway to ~50%; now a leaf keeps its full own approval.
        DebateGen.Debate memory debate = vm.createDebateWithFee(_deliberate, _ALICE, _LOCKING_DURATION, 1);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        vm.warpToRating(debate);
        // fee 100 -> net 9900: reserves (25, 10400), votes 10900
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);

        // Centered final price: floor(MAX * (10400-25)/10425) = 4274367931, standing 179 of 180
        // seconds (the neutral seed the first): floor(4274367931 * 179 / 180) = 4250621442 ~ 99.0%
        // conviction, folded with full weight.
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 4250621442);
        assertTrue(vm.outcome(debate));
    }

    function test_aCheapChildCorrectsInProportionToItsStake() public {
        // Burial repriced: under the fixed 50:50 blend a minimum-deposit con child owned half of
        // any parent's blend outright; now its pull is its stake share. A con child of 1000 at
        // 90% approval against a parent market of 10500 moves the blend from ~99% to ~83%,
        // not to near-zero.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 parent = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        vm.warpWindows(debate, 1); // the parent finalizes, so it can be replied to
        uint16 child = vm.addCon(debate, _CAROL, parent, 90);
        vm.warpToRating(debate);
        // fee 500 -> net 9500: reserves (25, 10000), votes 10500
        vm.stakePro(debate, _BOB, parent, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);

        // Child (leaf, untouched all window), centered: floor(MAX * (900-100)/1000) = 3435973836, subtree
        // stake 1000. Parent: its corrected price floor(MAX * (10000-25)/10025) = 4273546011 time-weights to
        // floor(4273546011 * 179 / 180) = 4249804088, and its stake to floor((1000*1 + 10500*179)/180)
        // = 10447. Blend: (4249804088 * 10447 - 3435973836 * 1000) / 11447 = 3578381189 ~ 83.3%.
        assertEq(vm.argumentOf(debate, child).subtreeVotes, 1000);
        assertEq(vm.argumentOf(debate, parent).subtreeVotes, 11447);
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 3578381189);
        assertTrue(vm.outcome(debate));
    }

    function test_siblingsWeighWithTheirWholeSubtreesStake() public {
        // Two pro siblings with equal own markets (1000 each): A a plain leaf at 90%, B seeded
        // neutral but carrying a sub-debate of 4000 at 90%. B's subtree (5000) outweighs A (1000)
        // at the thesis - under own-votes weighting they would count equally.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 90);
        uint16 b = vm.addPro(debate, _BOB, DebateGen.ROOT, 50);
        vm.warpWindows(debate, 1);
        vm.createArgument({
            debate: debate, author: _CAROL, parentId: b, isSupporting: true, initialApproval: 90, deposit: 4000
        });

        vm.warpToTallying(debate);
        vm.tally(debate);

        // A: floor(MAX * (900-100)/1000) = 3435973836, subtree 1000. C: floor(MAX * (3600-400)/4000) = 3435973836,
        // subtree 4000. B, seeded neutral, contributes zero of its own: blend
        // (0 * 1000 + 3435973836 * 4000) / 5000 = 2748779068, subtree 5000.
        // Thesis: (3435973836 * 1000 + 2748779068 * 5000) / 6000 = 2863311529 - the subtree-weighted mean,
        // not the own-votes mean (3092376452).
        assertEq(vm.argumentOf(debate, b).subtreeVotes, 5000);
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 2863311529);

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
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 90);
        uint16 attack = vm.addCon(debate, _BOB, DebateGen.ROOT, 50);
        vm.warpWindows(debate, 1);
        vm.createArgument({
            debate: debate, author: _CAROL, parentId: attack, isSupporting: false, initialApproval: 90, deposit: 3000
        });

        vm.warpToTallying(debate);
        vm.tally(debate);

        // The attack's rating: (0 * 1000 - 3435973836 * 3000) / 4000 = -2576980377, refuted - clamped
        // to zero at the fold. The supporter: floor(MAX * (900-100)/1000) = 3435973836, subtree 1000.
        // Thesis: (3435973836 * 1000 + 0 * 4000) / 5000 = 687194767 - diluted by the refuted subtree's
        // kept weight, not raised by it (unclamped it would read (3435973836 * 1000 + 2576980377 * 4000)
        // / 5000 = 2748779068, the attack aiding the thesis), and not the supporter's lone voice either.
        assertEq(vm.argumentOf(debate, attack).subtreeVotes, 4000);
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 687194767);
        assertTrue(vm.outcome(debate));
        assertEq(vm.argumentOf(debate, DebateGen.ROOT).subtreeVotes, vm.totalVotesOf(debate));
    }

    function test_aLastSecondSnipeBuysNeitherRatingNorWeight() public {
        // The attack the time-weighting exists to kill: push a thin neutral market to ~99% in the
        // rating window's final second. The final price reads 99% - but the seed's neutral price
        // stood all 180 seconds and the pushed price zero, so the tally reads exactly the seed:
        // no rating, and the pushed stake earns no weight either (held for zero seconds).
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        (,, uint48 ratingEndTime,) = _deliberate.phases(debate.id);
        vm.warp(ratingEndTime);
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS); // fee 500 -> net 9500: reserves (25, 10000)

        vm.warpToTallying(debate);
        vm.tally(debate);

        // The market closed at 10000/10025 ~ 99.8%, yet the tally saw a neutral market all window.
        assertEq(vm.approvalBps(debate, argumentId), 9975);
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 0);
        assertEq(vm.argumentOf(debate, argumentId).subtreeVotes, 1000);
        assertFalse(vm.outcome(debate));
    }

    function test_aStakeCarriesWeightForTheTimeItIsHeld() public {
        // A stake at the window's midpoint: the corrected price and the grown stake each stand 90
        // of 180 seconds, so both count at half. Half the window, half the voice.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        (, uint48 editingEndTime,,) = _deliberate.phases(debate.id);
        vm.warp(editingEndTime + 90);
        // fee 500 -> net 9500: reserves (25, 10000), votes 10500
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);

        // Price: floor(floor(MAX * (10000-25)/10025) * 90 / 180) = floor(4273546011 / 2) =
        // 2136773005. Weight: floor((1000 * 90 + 10500 * 90) / 180) = 5750 - the seed's 1000 in
        // full, the stake's 9500 at half.
        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 2136773005);
        assertEq(vm.argumentOf(debate, argumentId).subtreeVotes, 5750);
        assertTrue(vm.outcome(debate));
    }

    function test_aNeutralMarketSwaysNothingAndSilenceObjects() public {
        // The seed floor is the neutral point: a lone argument left at its 50% seed carries no
        // conviction either way, so the thesis nets exactly zero - and zero does not confirm.
        // Silence never approves a thesis; only positive net endorsement does.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);

        vm.warpToTallying(debate);
        vm.tally(debate);

        assertEq(vm.descendantsAggregate(debate, DebateGen.ROOT), 0);
        assertFalse(vm.outcome(debate));
    }
}
