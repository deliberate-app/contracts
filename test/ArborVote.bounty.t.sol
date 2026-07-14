// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IArborVote} from "../src/interfaces/IArborVote.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {MockERC20, MockERC20FeeOnTransfer} from "./mocks/MockERC20.m.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract ArborVoteBountyTest is Test {
    ArborVote internal _arborVote;
    MockERC20 internal _token;

    uint48 internal constant _LOCKING_DURATION = 1 * 60;
    uint256 internal constant _POOL = 300 ether;

    address internal _earlyStaker = makeAddr("earlyStaker");
    address internal _lateStaker = makeAddr("lateStaker");

    function setUp() public {
        _arborVote = new ArborVote(new MockIdentityRegistry());
        _token = new MockERC20();
        _token.mint(address(this), 1_000_000 ether);
        _token.approve(address(_arborVote), type(uint256).max);
    }

    // --- helpers ---

    function _createBountyDebate(uint256 bountyAmount) internal returns (uint256 debateId) {
        debateId = _arborVote.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            bountyToken: _token,
            bountyAmount: bountyAmount
        });
    }

    function _createBountylessDebate() internal returns (uint256 debateId) {
        debateId = _arborVote.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function _endEditing(uint256 debateId) internal {
        (, uint48 editingEndTime,,) = _arborVote.phases(debateId);
        vm.warp(editingEndTime + 1);
    }

    function _endRating(uint256 debateId) internal {
        (,, uint48 ratingEndTime,) = _arborVote.phases(debateId);
        vm.warp(ratingEndTime + 1);
    }

    /// @dev The profitable-early-staker choreography from the market tests: after the tally the early
    /// staker sits at 102 vote tokens (excess 2, still unredeemed), the late one at 99 (a loser), and
    /// three participants have joined (`100 * N = 300`).
    function _finishedBountyDebate() internal returns (uint256 debateId, uint16 argumentId) {
        debateId = _createBountyDebate(_POOL);
        _arborVote.join(debateId);
        argumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: "This is a good idea.",
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        vm.startPrank(_earlyStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 10);
        vm.stopPrank();

        vm.startPrank(_lateStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 20);
        vm.stopPrank();

        _endRating(debateId);
        _arborVote.tallyTree(debateId);
    }

    function _claimWindowEnd(uint256 debateId) internal view returns (uint48 closesAt) {
        (,,,, closesAt) = _arborVote.bounty(debateId);
    }

    // --- createDebate ---

    function test_createDebate_attachesTheBountyAtCreation() public {
        vm.expectEmit(true, true, true, true);
        emit IArborVote.BountyFunded({debateId: 0, funder: address(this), token: _token, amount: _POOL, pool: _POOL});
        uint256 debateId = _createBountyDebate(_POOL);

        (IERC20 token, uint256 pool, uint256 claimed, bool swept, uint48 claimEndTime) = _arborVote.bounty(debateId);
        assertEq(address(token), address(_token));
        assertEq(pool, _POOL);
        assertEq(claimed, 0);
        assertFalse(swept);
        // The window is unanchored until the tally runs.
        assertEq(claimEndTime, 0);
        assertEq(_token.balanceOf(address(_arborVote)), _POOL);
    }

    function test_createDebate_acceptsATokenWithoutFunding() public {
        uint256 debateId = _createBountyDebate(0);
        (IERC20 token, uint256 pool,,,) = _arborVote.bounty(debateId);
        assertEq(address(token), address(_token));
        assertEq(pool, 0);
    }

    function test_createDebate_revertsForAnAmountWithoutAToken() public {
        vm.expectRevert(ArborVote.BountyTokenZero.selector);
        _arborVote.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            bountyToken: IERC20(address(0)),
            bountyAmount: 1 ether
        });
    }

    // --- fundBounty ---

    function test_fundBounty_topsUpThePool() public {
        uint256 debateId = _createBountyDebate(_POOL);

        address donor = makeAddr("donor");
        _token.mint(donor, 50 ether);
        vm.startPrank(donor);
        _token.approve(address(_arborVote), 50 ether);
        vm.expectEmit(true, true, true, true);
        emit IArborVote.BountyFunded({
            debateId: debateId, funder: donor, token: _token, amount: 50 ether, pool: _POOL + 50 ether
        });
        _arborVote.fundBounty(debateId, 50 ether);
        vm.stopPrank();

        (, uint256 pool,,,) = _arborVote.bounty(debateId);
        assertEq(pool, _POOL + 50 ether);
    }

    function test_fundBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        vm.expectRevert(ArborVote.BountyMissing.selector);
        _arborVote.fundBounty(debateId, 1 ether);
    }

    function test_fundBounty_revertsForAZeroAmount() public {
        uint256 debateId = _createBountyDebate(_POOL);
        vm.expectRevert(ArborVote.BountyAmountZero.selector);
        _arborVote.fundBounty(debateId, 0);
    }

    function test_fundBounty_revertsOnceFinished() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseExceeded.selector, Phase.Status.Tallying, Phase.Status.Finished)
        );
        _arborVote.fundBounty(debateId, 1 ether);
    }

    function test_fundBounty_recordsWhatArrivesFromAFeeOnTransferToken() public {
        MockERC20FeeOnTransfer feeToken = new MockERC20FeeOnTransfer();
        feeToken.mint(address(this), 100 ether);
        feeToken.approve(address(_arborVote), type(uint256).max);

        uint256 debateId = _arborVote.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            bountyToken: feeToken,
            bountyAmount: 100 ether
        });

        // 10% burned in transit: the pool records the 90 that arrived, staying payable.
        (, uint256 pool,,,) = _arborVote.bounty(debateId);
        assertEq(pool, 90 ether);
        assertEq(feeToken.balanceOf(address(_arborVote)), 90 ether);
    }

    // --- join ---

    function test_join_countsParticipants() public {
        uint256 debateId = _createBountyDebate(_POOL);
        (,, uint32 participantsCount) = _arborVote.debates(debateId);
        assertEq(participantsCount, 0);

        _arborVote.join(debateId);
        vm.prank(_earlyStaker);
        _arborVote.join(debateId);

        (,, participantsCount) = _arborVote.debates(debateId);
        assertEq(participantsCount, 2);
    }

    // --- claimBounty ---

    function test_claimBounty_settlesAndPaysTheNetWinner() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();

        // Early staker: 102 vote tokens once redeemed -> excess 2 of the 300 initial supply.
        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;

        vm.expectEmit(true, true, true, true);
        emit IArborVote.BountyClaimed({debateId: debateId, account: _earlyStaker, excess: 2, amount: 2 ether});
        vm.prank(_earlyStaker);
        _arborVote.claimBounty(debateId, toSettle);

        // The claim settled the shares (102 tokens) and paid pool * 2/300.
        assertEq(_arborVote.getUserTokens(debateId, _earlyStaker), 102);
        assertEq(_token.balanceOf(_earlyStaker), 2 ether);
        (, uint256 pool, uint256 claimed,,) = _arborVote.bounty(debateId);
        assertEq(pool, _POOL);
        assertEq(claimed, 2 ether);
    }

    function test_claimBounty_acceptsAPreSettledClaim() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        _arborVote.redeemArgumentShares(debateId, argumentId, _earlyStaker);

        vm.prank(_earlyStaker);
        _arborVote.claimBounty(debateId, new uint16[](0));

        assertEq(_token.balanceOf(_earlyStaker), 2 ether);
    }

    function test_claimBounty_isOneShot() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;

        vm.startPrank(_earlyStaker);
        _arborVote.claimBounty(debateId, toSettle);
        vm.expectRevert(ArborVote.BountyAlreadyClaimed.selector);
        _arborVote.claimBounty(debateId, new uint16[](0));
        vm.stopPrank();
    }

    function test_claimBounty_revertsForAParticipantWithoutExcess() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;

        // The late staker redeemed 19 on 20 staked: 99 tokens is no win.
        vm.expectRevert(abi.encodeWithSelector(ArborVote.BountyNotWon.selector, 99));
        vm.prank(_lateStaker);
        _arborVote.claimBounty(debateId, toSettle);
    }

    function test_claimBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        _arborVote.join(debateId);
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        vm.expectRevert(ArborVote.BountyMissing.selector);
        _arborVote.claimBounty(debateId, new uint16[](0));
    }

    function test_claimBounty_revertsBeforeFinished() public {
        uint256 debateId = _createBountyDebate(_POOL);
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Editing)
        );
        _arborVote.claimBounty(debateId, new uint16[](0));
    }

    function test_claimBounty_revertsAfterTheClaimWindow() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);
        vm.warp(closesAt + 1);

        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;
        vm.expectRevert(abi.encodeWithSelector(ArborVote.ClaimWindowClosed.selector, closesAt));
        vm.prank(_earlyStaker);
        _arborVote.claimBounty(debateId, toSettle);
    }

    function test_claimBounty_marksAClaimEvenWhenItRoundsToZero() public {
        // A dust pool: 100 wei * 2/300 rounds to zero - the claim is still consumed and emits.
        uint256 debateId = _createBountyDebate(100);
        _arborVote.join(debateId);
        uint16 argumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: "This is a good idea.",
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);
        vm.startPrank(_earlyStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 10);
        vm.stopPrank();
        vm.startPrank(_lateStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 20);
        vm.stopPrank();
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;
        vm.expectEmit(true, true, true, true);
        emit IArborVote.BountyClaimed({debateId: debateId, account: _earlyStaker, excess: 2, amount: 0});
        vm.prank(_earlyStaker);
        _arborVote.claimBounty(debateId, toSettle);

        assertEq(_token.balanceOf(_earlyStaker), 0);
    }

    // --- sweepBounty ---

    function test_sweepBounty_paysTheRemainderToTheCreator() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        uint16[] memory toSettle = new uint16[](1);
        toSettle[0] = argumentId;
        vm.prank(_earlyStaker);
        _arborVote.claimBounty(debateId, toSettle);

        vm.warp(_claimWindowEnd(debateId) + 1);
        uint256 balanceBefore = _token.balanceOf(address(this));

        vm.expectEmit(true, true, true, true);
        emit IArborVote.BountySwept({debateId: debateId, creator: address(this), amount: _POOL - 2 ether});
        _arborVote.sweepBounty(debateId);

        assertEq(_token.balanceOf(address(this)) - balanceBefore, _POOL - 2 ether);
        (,,, bool swept,) = _arborVote.bounty(debateId);
        assertTrue(swept);
    }

    function test_sweepBounty_sweepsTheWholePoolWhenNobodyClaimed() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        uint256 balanceBefore = _token.balanceOf(address(this));
        _arborVote.sweepBounty(debateId);
        assertEq(_token.balanceOf(address(this)) - balanceBefore, _POOL);
    }

    function test_sweepBounty_revertsForNonCreators() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        vm.expectRevert(abi.encodeWithSelector(ArborVote.AddressInvalid.selector, address(this), _earlyStaker));
        vm.prank(_earlyStaker);
        _arborVote.sweepBounty(debateId);
    }

    function test_sweepBounty_revertsWhileTheClaimWindowIsOpen() public {
        (uint256 debateId,) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);

        vm.expectRevert(abi.encodeWithSelector(ArborVote.ClaimWindowOpen.selector, closesAt));
        _arborVote.sweepBounty(debateId);
    }

    function test_sweepBounty_isOneShot() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        _arborVote.sweepBounty(debateId);
        vm.expectRevert(ArborVote.BountyAlreadySwept.selector);
        _arborVote.sweepBounty(debateId);
    }

    function test_sweepBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        _arborVote.join(debateId);
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        vm.expectRevert(ArborVote.BountyMissing.selector);
        _arborVote.sweepBounty(debateId);
    }

    // --- bounty view ---

    function test_bounty_anchorsTheClaimWindowAtTheTally() public {
        (uint256 debateId,) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);
        assertEq(closesAt, uint48(vm.getBlockTimestamp()) + Parameters.CLAIM_WINDOW);
    }
}
