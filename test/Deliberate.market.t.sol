// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {Argument} from "../src/libs/Argument.sol";
import {DebateGen} from "./libs/DebateGen.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

// Forensic replay of production debate 4 (Base Sepolia, Deliberate 0xFb21…4A5b) and the isolated
// causes behind its counterintuitive numbers: 200 tokens staked, end balances 98 and 94, "total
// stake" shown as 191. Every production figure is re-derived from the mechanism alone, so a
// failing assert here would be an actual math bug - a passing suite pins each surprise on market
// economics instead.
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
        _deliberate = new Deliberate(new MockIdentityRegistry());
    }

    // The seed shared by every scenario: the production argument - a 10-token deposit at 50%
    // approval, splitting into 5/5 market reserves - warped into the rating phase.
    function _productionArgument() internal returns (DebateGen.Debate memory debate, uint16 argumentId) {
        debate = vm.createDebate(_deliberate, _ALICE, _LOCKING_DURATION);
        argumentId = vm.addArgument({
            debate: debate,
            author: _ALICE,
            parentId: DebateGen.ROOT,
            isSupporting: true,
            initialApproval: 50,
            deposit: 10
        });
        vm.warpToRating(debate);
    }

    function test_replaysProductionDebate4ToTheToken() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // 0x990c staked 100 UNDERRATED (the on-chain Staked event says isPro - not overrated):
        // 5% fee -> 95 net into the con reserve, pro restored to the invariant rounded up:
        // (5, 5) -> (1, 100), shares out 5 + 95 - 1 = 99.
        vm.stakePro(debate, _BOB, argumentId, 100);
        Argument.Data memory afterBob = vm.argumentOf(debate, argumentId);
        assertEq(afterBob.pro, 1);
        assertEq(afterBob.con, 100);
        assertEq(vm.sharesOf(debate, _BOB, argumentId).pro, 99);

        // 0x4161 then staked their remaining 90, also UNDERRATED: fee 4 -> 86 net,
        // (1, 100) -> (1, 186), shares out 1 + 86 - 1 = 86.
        vm.stakePro(debate, _ALICE, argumentId, 90);
        Argument.Data memory afterAlice = vm.argumentOf(debate, argumentId);
        assertEq(afterAlice.pro, 1);
        assertEq(afterAlice.con, 186);
        assertEq(vm.sharesOf(debate, _ALICE, argumentId).pro, 86);

        // The UI's "total stake" is the tokens sitting IN the markets: deposit + net stakes,
        // 10 + 95 + 86 = 191 = 200 gross - 9 fees. The fees moved to the creator, not vanished.
        assertEq(vm.totalVotesOf(debate), 191);
        assertEq(afterAlice.fees, 9);

        vm.warpToTallying(debate);
        vm.tally(debate);
        assertTrue(vm.outcome(debate));

        // A pro share redeems at the FINAL approval, con / (pro + con) = 186/187 - a price below
        // one token per share by construction, never a multiplier.
        vm.redeem(debate, _BOB, argumentId);
        vm.redeem(debate, _ALICE, argumentId);
        vm.claimFees(debate, argumentId);

        // The production end state, to the token: floor(99 * 186/187) = 98 for 0x990c, and
        // floor(86 * 186/187) = 85 plus the 9 creator fees = 94 for 0x4161.
        assertEq(vm.tokensOf(debate, _BOB), 98);
        assertEq(vm.tokensOf(debate, _ALICE), 94);

        // Conservation: of the 200 minted, 192 came back and 8 stay stranded in the market -
        // the spent seed deposit net of payout rounding, owned by nobody by design.
        assertEq(vm.tokensOf(debate, _BOB) + vm.tokensOf(debate, _ALICE), 192);
    }

    function test_aLoneCorrectorPaysForTheirOwnPriceMove() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // Bob's 95-net trade against the 10-token 50/50 seed IS the whole correction: it moves
        // the approval from 50% to 100/101 ~ 99% and he pays the average price along that curve.
        vm.stakePro(debate, _BOB, argumentId, 100);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);

        // floor(99 * 100/101) = 98: the same payout as the replay, where Alice's later stake
        // nudged the approval to 186/187 - rounding eats that +0.5%, so the second corrector
        // added nothing Bob could cash in. An AMM pays for moves OTHERS make after you; his own
        // move cost the curve's average price, and the 5-token fee exceeded the 3-token gain.
        assertEq(vm.tokensOf(debate, _BOB), 98);
    }

    function test_aOnePercentFeeTurnsTheLoneCorrectorProfitable() public {
        // The same lone-corrector scenario at the frontend's new default fee of 1% instead of the
        // replayed era's 5%: fee 1 -> 99 net, (5, 5) -> (1, 104), shares 5 + 99 - 1 = 103.
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
        vm.stakePro(debate, _BOB, argumentId, 100);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);

        // floor(103 * 104/105) = 102: the curve gain now exceeds the fee, so the identical trade
        // that lost 2 tokens at 5% earns 2 at 1% - the fee level, not the market math, decided.
        assertEq(vm.feeOf(debate), 1);
        assertEq(vm.tokensOf(debate, _BOB), 102);
    }

    function test_profitNeedsACounterpartyOnTheWrongSide() public {
        (DebateGen.Debate memory debate, uint16 argumentId) = _productionArgument();

        // The outcome the intuition expected, reconstructed: Carol calls the argument overrated
        // and is wrong - her 95 net crashes the approval to ~1% ((5, 5) -> (100, 1), 99 con
        // shares). Bob then buys the pro side cheap: (100, 1) -> (2, 96), 100 + 95 - 2 = 193 pro
        // shares for the same 100-token stake that bought only 99 in the replay.
        vm.stakeCon(debate, _CAROL, argumentId, 100);
        vm.stakePro(debate, _BOB, argumentId, 100);

        vm.warpToTallying(debate);
        vm.tally(debate);
        vm.redeem(debate, _BOB, argumentId);
        vm.redeem(debate, _CAROL, argumentId);

        // Final approval 96/98: Bob redeems floor(193 * 96/98) = 189, Carol floor(99 * 2/98) = 2.
        // "Many more points at the expense of the other" requires opposing sides; in production
        // both stakes were pro, so the only tokens winnable were the 10-token seed.
        assertEq(vm.tokensOf(debate, _BOB), 189);
        assertEq(vm.tokensOf(debate, _CAROL), 2);
    }
}
