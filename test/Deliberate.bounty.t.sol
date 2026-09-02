// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {IDeliberate} from "../src/interfaces/IDeliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {MockERC20, MockERC20FeeOnTransfer} from "./mocks/MockERC20.m.sol";

// Vote amounts are in the contract's unit, a hundredth of a vote token; the bounty is an ERC-20 in wei.
contract DeliberateBountyTest is Test {
    Deliberate internal _deliberate;
    MockERC20 internal _token;

    uint48 internal constant _LOCKING_DURATION = 1 minutes;
    uint256 internal constant _POOL = 300 ether;

    address internal _earlyStaker = makeAddr("earlyStaker");
    address internal _lateStaker = makeAddr("lateStaker");

    function setUp() public {
        _deliberate = new Deliberate();
        _token = new MockERC20();
        _token.mint(address(this), 1_000_000 ether);
        _token.approve(address(_deliberate), type(uint256).max);
    }

    // --- helpers ---

    function _createBountyDebate(uint256 bountyAmount) internal returns (uint256 debateId) {
        debateId = _createDebate(_token, bountyAmount);
    }

    function _createBountylessDebate() internal returns (uint256 debateId) {
        debateId = _createDebate(IERC20(address(0)), 0);
    }

    function _createDebate(IERC20 bountyToken, uint256 bountyAmount) internal returns (uint256 debateId) {
        debateId = _deliberate.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: 5,
            identityRegistry: IIdentityRegistry(address(0)),
            bountyToken: bountyToken,
            bountyAmount: bountyAmount
        });
    }

    function _endEditing(uint256 debateId) internal {
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);
        vm.warp(editingEndTime + 1);
    }

    function _endRating(uint256 debateId) internal {
        (,, uint48 ratingEndTime,) = _deliberate.phases(debateId);
        vm.warp(ratingEndTime + 1);
    }

    // The profitable-early-staker choreography from the unit tests: after the tally the early staker sits at
    // 10245 once redeemed (excess 245), the late one at 9948 (a loser), and three participants have joined,
    // so the initial supply the excess is measured against is 3 * 10000 = 30000.
    function _finishedBountyDebate() internal returns (uint256 debateId, uint16 argumentId) {
        (debateId, argumentId) = _finishedBountyDebate(_POOL);
    }

    function _finishedBountyDebate(uint256 pool) internal returns (uint256 debateId, uint16 argumentId) {
        debateId = _createBountyDebate(pool);
        _deliberate.join(debateId);
        argumentId = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: "This is a good idea.",
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        _endEditing(debateId);

        vm.startPrank(_earlyStaker);
        _deliberate.join(debateId);
        _deliberate.stakePro(debateId, argumentId, 1000);
        vm.stopPrank();

        vm.startPrank(_lateStaker);
        _deliberate.join(debateId);
        _deliberate.stakePro(debateId, argumentId, 2000);
        vm.stopPrank();

        _endRating(debateId);
        _deliberate.tallyTree(debateId);
    }

    function _settling(uint16 argumentId) internal pure returns (uint16[] memory argumentIds) {
        argumentIds = new uint16[](1);
        argumentIds[0] = argumentId;
    }

    function _claimWindowEnd(uint256 debateId) internal view returns (uint48 closesAt) {
        (,,,, closesAt) = _deliberate.bounty(debateId);
    }

    // --- createDebate ---

    function test_createDebate_attachesTheBountyAtCreation() public {
        vm.expectEmit();
        emit IDeliberate.BountyFunded({debateId: 0, funder: address(this), token: _token, amount: _POOL, pool: _POOL});
        uint256 debateId = _createBountyDebate(_POOL);

        (IERC20 token, uint256 pool, uint256 claimed, bool swept, uint48 claimEndTime) = _deliberate.bounty(debateId);
        assertEq(address(token), address(_token));
        assertEq(pool, _POOL);
        assertEq(claimed, 0);
        assertFalse(swept);
        // The window is unanchored until the tally runs.
        assertEq(claimEndTime, 0);
        assertEq(_token.balanceOf(address(_deliberate)), _POOL);
    }

    function test_createDebate_acceptsATokenWithoutFunding() public {
        uint256 debateId = _createBountyDebate(0);
        (IERC20 token, uint256 pool,,,) = _deliberate.bounty(debateId);
        assertEq(address(token), address(_token));
        assertEq(pool, 0);
    }

    function test_createDebate_revertsForAnAmountWithoutAToken() public {
        vm.expectRevert(Deliberate.BountyTokenZero.selector);
        _createDebate(IERC20(address(0)), 1 ether);
    }

    // --- fundBounty ---

    function test_fundBounty_topsUpThePool() public {
        uint256 debateId = _createBountyDebate(_POOL);

        address donor = makeAddr("donor");
        _token.mint(donor, 50 ether);
        vm.startPrank(donor);
        _token.approve(address(_deliberate), 50 ether);
        vm.expectEmit();
        emit IDeliberate.BountyFunded({
            debateId: debateId, funder: donor, token: _token, amount: 50 ether, pool: _POOL + 50 ether
        });
        _deliberate.fundBounty(debateId, 50 ether);
        vm.stopPrank();

        (, uint256 pool,,,) = _deliberate.bounty(debateId);
        assertEq(pool, _POOL + 50 ether);
    }

    function test_fundBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        vm.expectRevert(Deliberate.BountyMissing.selector);
        _deliberate.fundBounty(debateId, 1 ether);
    }

    function test_fundBounty_revertsForAZeroAmount() public {
        uint256 debateId = _createBountyDebate(_POOL);
        vm.expectRevert(Deliberate.BountyAmountZero.selector);
        _deliberate.fundBounty(debateId, 0);
    }

    function test_fundBounty_revertsOnceFinished() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseExceeded.selector, Phase.Status.Tallying, Phase.Status.Finished)
        );
        _deliberate.fundBounty(debateId, 1 ether);
    }

    function test_fundBounty_recordsWhatArrivesFromAFeeOnTransferToken() public {
        MockERC20FeeOnTransfer feeToken = new MockERC20FeeOnTransfer();
        feeToken.mint(address(this), 100 ether);
        feeToken.approve(address(_deliberate), type(uint256).max);

        uint256 debateId = _createDebate(feeToken, 100 ether);

        // 10% burned in transit: the pool records the 90 that arrived, staying payable.
        (, uint256 pool,,,) = _deliberate.bounty(debateId);
        assertEq(pool, 90 ether);
        assertEq(feeToken.balanceOf(address(_deliberate)), 90 ether);
    }

    // --- join ---

    function test_join_countsParticipants() public {
        uint256 debateId = _createBountyDebate(_POOL);
        (,, uint32 participantsCount,,) = _deliberate.debates(debateId);
        assertEq(participantsCount, 0);

        _deliberate.join(debateId);
        vm.prank(_earlyStaker);
        _deliberate.join(debateId);

        (,, participantsCount,,) = _deliberate.debates(debateId);
        assertEq(participantsCount, 2);
    }

    // --- claimBounty ---

    function test_claimBounty_settlesAndPaysTheNetWinner() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();

        // Early staker: 10245 once redeemed -> excess 245 of the 30000 initial supply.
        vm.expectEmit();
        emit IDeliberate.BountyClaimed({debateId: debateId, account: _earlyStaker, excess: 245, amount: 2.45 ether});
        vm.prank(_earlyStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));

        // The claim settled the shares (10245) and paid pool * 245 / 30000.
        assertEq(_deliberate.getUserTokens(debateId, _earlyStaker), 10245);
        assertEq(_token.balanceOf(_earlyStaker), 2.45 ether);
        (, uint256 pool, uint256 claimed,,) = _deliberate.bounty(debateId);
        assertEq(pool, _POOL);
        assertEq(claimed, 2.45 ether);
    }

    function test_claimBounty_acceptsAPreSettledClaim() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        _deliberate.redeemArgumentShares(debateId, argumentId, _earlyStaker);

        vm.prank(_earlyStaker);
        _deliberate.claimBounty(debateId, new uint16[](0));

        assertEq(_token.balanceOf(_earlyStaker), 2.45 ether);
    }

    function test_claimBounty_isOneShot() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();

        vm.startPrank(_earlyStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));
        vm.expectRevert(Deliberate.BountyAlreadyClaimed.selector);
        _deliberate.claimBounty(debateId, new uint16[](0));
        vm.stopPrank();
    }

    function test_claimBounty_revertsForAParticipantWithoutExcess() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();

        // The late staker redeemed 1948 on 2000 staked: 9948 is no win.
        vm.expectRevert(abi.encodeWithSelector(Deliberate.BountyNotWon.selector, 9948));
        vm.prank(_lateStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));
    }

    function test_claimBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        _deliberate.join(debateId);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        vm.expectRevert(Deliberate.BountyMissing.selector);
        _deliberate.claimBounty(debateId, new uint16[](0));
    }

    function test_claimBounty_revertsBeforeFinished() public {
        uint256 debateId = _createBountyDebate(_POOL);
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Editing)
        );
        _deliberate.claimBounty(debateId, new uint16[](0));
    }

    function test_claimBounty_revertsAfterTheClaimWindow() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);
        vm.warp(closesAt + 1);
        vm.expectRevert(abi.encodeWithSelector(Deliberate.ClaimWindowClosed.selector, closesAt));
        vm.prank(_earlyStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));
    }

    function test_claimBounty_marksAClaimEvenWhenItRoundsToZero() public {
        // A dust pool: 100 wei * 245 / 30000 rounds to zero - the claim is still consumed and emits.
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate(100);
        vm.expectEmit();
        emit IDeliberate.BountyClaimed({debateId: debateId, account: _earlyStaker, excess: 245, amount: 0});
        vm.prank(_earlyStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));

        assertEq(_token.balanceOf(_earlyStaker), 0);
    }

    // --- sweepBounty ---

    function test_sweepBounty_paysTheRemainderToTheCreator() public {
        (uint256 debateId, uint16 argumentId) = _finishedBountyDebate();
        vm.prank(_earlyStaker);
        _deliberate.claimBounty(debateId, _settling(argumentId));

        vm.warp(_claimWindowEnd(debateId) + 1);
        uint256 balanceBefore = _token.balanceOf(address(this));

        vm.expectEmit();
        emit IDeliberate.BountySwept({debateId: debateId, creator: address(this), amount: _POOL - 2.45 ether});
        _deliberate.sweepBounty(debateId);

        assertEq(_token.balanceOf(address(this)) - balanceBefore, _POOL - 2.45 ether);
        (,,, bool swept,) = _deliberate.bounty(debateId);
        assertTrue(swept);
    }

    function test_sweepBounty_sweepsTheWholePoolWhenNobodyClaimed() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        uint256 balanceBefore = _token.balanceOf(address(this));
        _deliberate.sweepBounty(debateId);
        assertEq(_token.balanceOf(address(this)) - balanceBefore, _POOL);
    }

    function test_sweepBounty_revertsForNonCreators() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.AddressInvalid.selector, address(this), _earlyStaker));
        vm.prank(_earlyStaker);
        _deliberate.sweepBounty(debateId);
    }

    function test_sweepBounty_revertsWhileTheClaimWindowIsOpen() public {
        (uint256 debateId,) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ClaimWindowOpen.selector, closesAt));
        _deliberate.sweepBounty(debateId);
    }

    function test_sweepBounty_isOneShot() public {
        (uint256 debateId,) = _finishedBountyDebate();
        vm.warp(_claimWindowEnd(debateId) + 1);

        _deliberate.sweepBounty(debateId);
        vm.expectRevert(Deliberate.BountyAlreadySwept.selector);
        _deliberate.sweepBounty(debateId);
    }

    function test_sweepBounty_revertsWithoutABounty() public {
        uint256 debateId = _createBountylessDebate();
        _deliberate.join(debateId);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        vm.expectRevert(Deliberate.BountyMissing.selector);
        _deliberate.sweepBounty(debateId);
    }

    // --- bounty view ---

    function test_bounty_anchorsTheClaimWindowAtTheTally() public {
        (uint256 debateId,) = _finishedBountyDebate();
        uint48 closesAt = _claimWindowEnd(debateId);
        assertEq(closesAt, uint48(vm.getBlockTimestamp()) + Parameters.CLAIM_WINDOW);
    }
}
