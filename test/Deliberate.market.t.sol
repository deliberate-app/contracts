// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {Argument} from "../src/libs/Argument.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {DebateGen} from "./libs/DebateGen.sol";

// Forensic replay of production debate 4's trades (Base Sepolia, Deliberate 0xFb21…4A5b) and the isolated
// causes behind its counterintuitive numbers: the whole budget staked, end balances short of it, "total
// stake" shown as 191. Every figure is re-derived from the mechanism alone, so a failing assert here would
// be an actual math bug - a passing suite pins each surprise on market economics instead. The era held
// whole vote tokens; the contract now holds hundredths, so the trades replay at a hundred times the scale
// with the finer rounding the extra digits allow. And a share now settles at the tallied rating built from
// time-weighted prices, not at the closing price the era paid; where the mechanisms disagree the comments
// say so.
contract DeliberateMarketTest is Test {
    using DebateGen for Vm;

    uint48 internal constant _LOCKING_DURATION = 1 minutes;

    // The production actors: _ALICE stands in for 0x4161… (debate + argument creator, second
    // staker), _BOB for 0x990c… (first staker). _CAROL joins only in the counterfactual.
    address internal immutable _ALICE = makeAddr("alice");
    address internal immutable _BOB = makeAddr("bob");
    address internal immutable _CAROL = makeAddr("carol");

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate();
    }

    // The seed shared by every scenario: the production argument - the minimum deposit of 1000 at 50%
    // approval, splitting into (500, 500) market reserves - warped into the rating phase.
    function _productionArgument() internal returns (DebateGen.Debate memory debate, uint16 argumentId) {
        debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        vm.warpToRating(debate);
    }

    function test_replaysProductionDebate4sTrades() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // 0x990c staked their whole budget UNDERRATED (the on-chain Staked event says isPro - not
        // overrated): 5% fee -> 9500 net into the con reserve, pro restored to the invariant rounded up:
        // (500, 500) -> (25, 10000), shares out 500 + 9500 - 25 = 9975.
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);
        Argument.Data memory afterBob = vm.argumentOf(debate, argumentId);
        assertEq(afterBob.pro, 25);
        assertEq(afterBob.con, 10000);
        assertEq(vm.sharesOf(debate, _BOB, argumentId).pro, 9975);

        // 0x4161 then staked their remaining nine tenths, also UNDERRATED: fee 450 -> 8550 net,
        // (25, 10000) -> (14, 18550), shares out 25 + 8550 - 14 = 8561.
        vm.stakePro(debate, _ALICE, argumentId, Parameters.INITIAL_TOKENS - Parameters._MIN_DEBATE_DEPOSIT);
        Argument.Data memory afterAlice = vm.argumentOf(debate, argumentId);
        assertEq(afterAlice.pro, 14);
        assertEq(afterAlice.con, 18550);
        assertEq(vm.sharesOf(debate, _ALICE, argumentId).pro, 8561);

        // The UI's "total stake" is the tokens sitting IN the markets: deposit + net stakes,
        // 1000 + 9500 + 8550 = 19050 = 19000 gross plus the deposit, less 950 in fees. The fees moved
        // to the creator, not vanished.
        assertEq(vm.totalVotesOf(debate), 19050);
        assertEq(afterAlice.fees, 950);

        vm.warpToTallying(debate);
        vm.tally(debate);
        assertTrue(vm.outcome(debate));

        // A pro share settles at the tallied rating - for this childless argument its own
        // time-weighted price, a hair under the closing 18550/18564 (the neutral seed stood the
        // window's first second) - below one per share by construction, never a multiplier.
        vm.redeem(debate, _BOB, argumentId);
        vm.redeem(debate, _ALICE, argumentId);
        vm.claimFees(debate, argumentId);

        // The end state: 9939 for 0x990c, and 8530 plus the 950 creator fees
        // = 9480 for 0x4161.
        assertEq(vm.tokensOf(debate, _BOB), 9939);
        assertEq(vm.tokensOf(debate, _ALICE), 9480);

        // Conservation: of the 20000 minted, 19419 came back and the rest stays stranded in the
        // market - the spent seed deposit net of payout rounding, owned by nobody by design.
        assertEq(vm.tokensOf(debate, _BOB) + vm.tokensOf(debate, _ALICE), 19419);
    }

    function test_aLoneCorrectorPaysForTheirOwnPriceMove() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // Bob's 9500-net trade against the 50/50 seed of 1000 IS the whole correction: it moves
        // the approval from 50% to 10000/10025 ~ 99.8% and he pays the average price along that curve.
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);

        // 9922 back on 10000 staked: his shares settle at the time-weighted price he set, below the
        // closing price alone. An AMM pays for moves OTHERS make after you; his own move cost the
        // curve's average price, and the fee of 500 ate more than the curve gain.
        assertEq(vm.tokensOf(debate, _BOB), 9922);
    }

    function test_aOnePercentFeeTurnsTheLoneCorrectorProfitable() public {
        // The same lone-corrector scenario at the frontend's new default fee of 1% instead of the
        // replayed era's 5%: fee 100 -> 9900 net, (500, 500) -> (25, 10400), shares 500 + 9900 - 25 = 10375.
        DebateGen.Debate memory debate = vm.createDebateWithFee(_deliberate, _ALICE, _LOCKING_DURATION, 1);
        uint16 argumentId = vm.addPro(debate, _ALICE, DebateGen.ROOT, 50);
        vm.warpToRating(debate);
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);

        // 10321 back on 10000 staked: the curve gain now exceeds the fee, so the identical trade that
        // lost tokens at 5% earns them at 1% - the fee level, not the market math, decided.
        assertEq(vm.feeOf(debate), 1);
        assertEq(vm.tokensOf(debate, _BOB), 10321);
    }

    function test_profitNeedsACounterpartyOnTheWrongSide() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // The outcome the intuition expected, reconstructed: Carol calls the argument overrated
        // and is wrong - her 9500 net crashes the approval ((500, 500) -> (10000, 25), 9975 con
        // shares). Bob then buys the pro side cheap: (10000, 25) -> (27, 9525), 10000 + 9500 - 27 =
        // 19473 pro shares for the same stake of 10000 that bought only 9975 in the replay.
        vm.stakeCon(debate, _CAROL, argumentId, Parameters.INITIAL_TOKENS);
        vm.stakePro(debate, _BOB, argumentId, Parameters.INITIAL_TOKENS);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);
        vm.redeem(debate, _CAROL, argumentId);

        // The shares settle at the market's time-weighted rating. "Many more points at the expense
        // of the other" requires opposing sides; in the replay both stakes were pro, so the only
        // tokens winnable were the seed.
        assertEq(vm.tokensOf(debate, _BOB), 19364);
        assertEq(vm.tokensOf(debate, _CAROL), 55);
    }

    function test_refutationByChildrenSettlesTheParentsShares() public {
        // The trade price settlement could never pay: Bob calls a 90%-seeded argument overrated
        // with a tiny early con stake that barely moves its market - and a counter-argument
        // backed by 3000 demolishes the argument from below. Under price settlement the lazy
        // market shielded the argument (Bob's 533 con shares would pay floor(533 * 195/657) = 158); settling at
        // the tallied rating, the sub-debate corrects what his shares are worth.
        DebateGen.Debate memory debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        uint16 parent = vm.addPro(debate, _ALICE, DebateGen.ROOT, 90);
        vm.warpWindows(debate, 1); // the parent finalizes, so it can be replied to
        vm.createArgument({
            debate: debate, author: _CAROL, parentId: parent, isSupporting: false, initialApproval: 90, deposit: 3000
        });
        vm.warpToRating(debate);
        vm.stakeCon(debate, _BOB, parent, 100); // fee 5 -> net 95: reserves (195, 462), 533 con shares

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, parent);

        // The parent's own market closed pro-leaning, yet its rating - its time-weighted price at
        // stake 1000 against the counter-argument's 90% conviction at subtree stake 3000 - lands
        // refuted at -2048884181 ~ -48%. Bob's con shares settle against that rating rather than against
        // the lazy market that shielded the argument: floor(533 * 6343851476 / 8589934590) = 393, so
        // 10000 - 100 + 393.
        assertEq(vm.argumentOf(debate, parent).rating, -2048884181);
        assertEq(vm.tokensOf(debate, _BOB), 10293);
        // And toward the thesis the refuted parent is silenced, not inverted: silence objects.
        assertFalse(vm.outcome(debate));
    }
}
