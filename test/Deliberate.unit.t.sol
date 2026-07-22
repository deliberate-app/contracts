// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {IDeliberate} from "../src/interfaces/IDeliberate.sol";
import {Argument} from "../src/libs/Argument.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {User} from "../src/libs/User.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract DeliberateTest is Test {
    Deliberate internal _deliberate;

    MockIdentityRegistry internal _mockIdentityRegistry;

    uint48 internal constant _LOCKING_DURATION = 1 * 60; // 1 minute
    bytes32 internal constant _THESIS_CONTENT = "We should do XYZ";
    bytes32 internal constant _PRO_ARGUMENT_CONTENT = "This is a good idea.";
    uint16 internal constant _ROOT_ARGUMENT_ID = 0;

    function setUp() public {
        _mockIdentityRegistry = new MockIdentityRegistry();
        _deliberate = new Deliberate(_mockIdentityRegistry);
    }

    // --- helpers ---

    function _createDebate() internal returns (uint256 debateId) {
        // The classic 7/3 split: editing spans seven locking windows, rating three.
        debateId = _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: 5,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function _createDebateWithFee(uint32 feePercentage) internal returns (uint256 debateId) {
        debateId = _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: feePercentage,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function _join(uint256 debateId) internal {
        _deliberate.join(debateId);
    }

    function _addArgument(uint256 debateId, bool isSupporting, uint32 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = _addArgument(debateId, isSupporting, initialApproval, Parameters._MIN_DEBATE_DEPOSIT);
    }

    function _addArgument(uint256 debateId, bool isSupporting, uint32 initialApproval, uint32 deposit)
        internal
        returns (uint16 argumentId)
    {
        argumentId = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: isSupporting,
            initialApproval: initialApproval,
            deposit: deposit
        });
    }

    function _assertLeafSet(uint256 debateId, uint16[] memory expectedIds) internal view {
        uint16[] memory actualIds = _deliberate.getLeafArgumentIds(debateId);
        assertEq(actualIds.length, expectedIds.length);
        for (uint256 i = 0; i < expectedIds.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < actualIds.length; j++) {
                if (actualIds[j] == expectedIds[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found);
        }
    }

    function _fillDebateToTheArgumentCap(uint256 debateId) internal {
        uint16 maxArguments = Parameters.MAX_ARGUMENTS;
        uint16 added = 0; // the thesis already counts toward the cap
        uint256 participantIndex = 0;
        while (added < maxArguments - 1) {
            address participant = makeAddr(string.concat("participant", vm.toString(participantIndex)));
            vm.startPrank(participant);
            _deliberate.join(debateId);
            // Each participant's budget affords ten argument deposits.
            for (uint256 i = 0; i < 10 && added < maxArguments - 1; i++) {
                _deliberate.addArgument({
                    debateId: debateId,
                    parentArgumentId: _ROOT_ARGUMENT_ID,
                    contentURI: _PRO_ARGUMENT_CONTENT,
                    isSupporting: added % 2 == 0,
                    initialApproval: 50,
                    deposit: Parameters._MIN_DEBATE_DEPOSIT
                });
                added++;
            }
            vm.stopPrank();
            participantIndex++;
        }
    }

    function _endEditing(uint256 debateId) internal {
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);
        vm.warp(editingEndTime + 1);
    }

    function _endRating(uint256 debateId) internal {
        (,, uint48 ratingEndTime,) = _deliberate.phases(debateId);
        vm.warp(ratingEndTime + 1);
    }

    // --- phase derivation ---

    function test_phases_derivesEditingRatingTallyingFromTheClockWithoutAPoke() public {
        uint256 debateId = _createDebate();

        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));

        // Crossing a time gate advances the phase on read - no transaction moves it.
        vm.warp(editingEndTime + 1);
        (currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Rating));

        vm.warp(ratingEndTime + 1);
        (currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Tallying));
    }

    function test_phases_holdEditingUpToButNotPastTheEditingGate() public {
        uint256 debateId = _createDebate();
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);

        // The gate is exclusive: exactly at the end time the debate is still editing.
        vm.warp(editingEndTime);
        (Phase.Status currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));
    }

    function test_phases_reachFinishedOnlyThroughTheTallyLatchNotTheClock() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        // The clock alone never reaches Finished, however far it advances.
        vm.warp(type(uint32).max);
        (Phase.Status currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Tallying));

        _deliberate.tallyTree(debateId);
        (currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));

        // Finished is terminal: no later time leaves it.
        vm.warp(type(uint40).max);
        (currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));
    }

    // --- createDebate ---

    function test_createDebate_isUninitializedBeforeADebateIsCreated() public view {
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 lockingDuration) =
            _deliberate.phases(0);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Uninitialized));
        assertEq(editingEndTime, 0);
        assertEq(ratingEndTime, 0);
        assertEq(lockingDuration, 0);
    }

    function test_createDebate_incrementsTheDebateId() public {
        uint256 debateId = _createDebate();
        assertEq(debateId, 0);

        debateId = _createDebate();
        assertEq(debateId, 1);
    }

    function test_debatesCount_countsCreatedDebates() public {
        assertEq(_deliberate.debatesCount(), 0);

        _createDebate();
        assertEq(_deliberate.debatesCount(), 1);

        _createDebate();
        assertEq(_deliberate.debatesCount(), 2);
    }

    function test_createDebate_storesTheChosenFee() public {
        uint256 debateId = _createDebate();
        (,,, uint32 feePercentage) = _deliberate.debates(debateId);
        assertEq(feePercentage, 5);
    }

    function test_createDebate_acceptsAZeroAndTheMaximumFee() public {
        uint256 freeDebateId = _createDebateWithFee(0);
        (,,, uint32 freeFee) = _deliberate.debates(freeDebateId);
        assertEq(freeFee, 0);

        uint256 maxDebateId = _createDebateWithFee(99);
        (,,, uint32 maxFee) = _deliberate.debates(maxDebateId);
        assertEq(maxFee, 99);
    }

    function test_createDebate_revertsForAFeeAbove99() public {
        vm.expectRevert(abi.encodeWithSelector(Deliberate.FeePercentageExceeded.selector, 99, 100));
        _createDebateWithFee(100);
    }

    function test_quoteStake_usesTheDebatesFee() public {
        // A 1% debate charges 1 on a 100-token stake; the standing 5% helper charges 5.
        uint256 onePercentId = _createDebateWithFee(1);
        assertEq(
            _deliberate.quoteStake({debateId: onePercentId, argumentId: 1, isPro: true, voteTokenAmount: 100}).fee, 1
        );

        uint256 fivePercentId = _createDebate();
        assertEq(
            _deliberate.quoteStake({debateId: fivePercentId, argumentId: 1, isPro: true, voteTokenAmount: 100}).fee, 5
        );
    }

    function test_createDebate_initializesThePhaseData() public {
        uint256 debateId = _createDebate();

        uint256 currentTime = vm.getBlockTimestamp();
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 lockingDuration) =
            _deliberate.phases(debateId);

        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));
        assertEq(lockingDuration, _LOCKING_DURATION);
        assertEq(editingEndTime, currentTime + 7 * _LOCKING_DURATION);
        assertEq(ratingEndTime, currentTime + 10 * _LOCKING_DURATION);
    }

    function test_createDebate_revertsForAZeroLockingDuration() public {
        vm.expectRevert(Deliberate.LockingDurationZero.selector);
        _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: 0,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: 5,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function test_createDebate_setsTheChosenDurations() public {
        // The three times are independent: a short locking window inside long, uneven phases.
        uint256 debateId = _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: 30 minutes,
            editingDuration: 3 days,
            ratingDuration: 1 days,
            feePercentage: 5,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });

        uint256 currentTime = vm.getBlockTimestamp();
        (, uint48 editingEndTime, uint48 ratingEndTime, uint48 lockingDuration) = _deliberate.phases(debateId);
        assertEq(lockingDuration, 30 minutes);
        assertEq(editingEndTime, currentTime + 3 days);
        assertEq(ratingEndTime, currentTime + 3 days + 1 days);
    }

    function test_createDebate_revertsForAnEditingPhaseNotExceedingTheLocking() public {
        // The bound is strict: an editing phase equal to the locking duration fits no reply window.
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.DurationTooShort.selector, _LOCKING_DURATION, _LOCKING_DURATION)
        );
        _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingDuration: _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: 5,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function test_createDebate_revertsForARatingPhaseShorterThanTheLocking() public {
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.DurationTooShort.selector, _LOCKING_DURATION, _LOCKING_DURATION - 1)
        );
        _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: _LOCKING_DURATION - 1,
            feePercentage: 5,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function test_createDebate_initializesTheRootArgument() public {
        uint256 debateId = _createDebate();

        Argument.Data memory rootArgument = _deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID);
        assertEq(rootArgument.contentURI, _THESIS_CONTENT);

        assertEq(rootArgument.pro, 0);
        assertEq(rootArgument.con, 0);
        assertEq(rootArgument.votes, 0);
        assertEq(rootArgument.fees, 0);

        assertEq(rootArgument.creator, address(this));
        // The thesis is final from creation: its finalization time is the creation time itself.
        assertEq(rootArgument.finalizationTime, uint48(vm.getBlockTimestamp()));

        assertEq(rootArgument.isSupporting, false);
        assertEq(rootArgument.parentArgumentId, 0);
        assertEq(rootArgument.subtreeVotes, 0);

        assertEq(_deliberate.getLeafArgumentIds(debateId).length, 0);
    }

    // --- join ---

    function test_join_joinsADebate() public {
        uint256 debateId = _createDebate();

        assertEq(uint256(_deliberate.getUserRole(debateId, address(this))), uint256(User.Role.Unassigned));
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 0);

        User.Shares memory shares = _deliberate.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);

        _join(debateId);

        assertEq(uint256(_deliberate.getUserRole(debateId, address(this))), uint256(User.Role.Participant));
        assertEq(_deliberate.getUserTokens(debateId, address(this)), Parameters.INITIAL_TOKENS);

        shares = _deliberate.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);
    }

    function test_join_revertsIfTheUserHasNoValidIdentityProof() public {
        uint256 debateId = _createDebate();

        _mockIdentityRegistry.deny(address(this));

        vm.expectRevert(Deliberate.IdentityProofInvalid.selector);
        _deliberate.join(debateId);
    }

    function test_join_succeedsDuringTheRatingPhase() public {
        uint256 debateId = _createDebate();
        _endEditing(debateId);

        _join(debateId);

        assertEq(uint256(_deliberate.getUserRole(debateId, address(this))), uint256(User.Role.Participant));
    }

    function test_join_revertsForAnUninitializedDebate() public {
        uint256 uninitializedDebateId = 123;

        vm.expectRevert(abi.encodeWithSelector(Deliberate.DebateUninitialized.selector, uninitializedDebateId));
        _deliberate.join(uninitializedDebateId);
    }

    function test_join_revertsOnceRatingHasEnded() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseExceeded.selector, Phase.Status.Rating, Phase.Status.Tallying)
        );
        _deliberate.join(debateId);

        _deliberate.tallyTree(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseExceeded.selector, Phase.Status.Rating, Phase.Status.Finished)
        );
        _deliberate.join(debateId);
    }

    function test_join_revertsForAnAlreadyJoinedAccount() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.RoleInvalid.selector, User.Role.Unassigned, User.Role.Participant)
        );
        _deliberate.join(debateId);
    }

    // --- addArgument ---

    function test_addArgument_incrementsTheArgumentId() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        assertEq(_addArgument(debateId, true, 50), 1);
        assertEq(_addArgument(debateId, true, 50), 2);
    }

    function test_addArgument_addsAProArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 proArgumentId = _addArgument(debateId, true, 50);

        Argument.Data memory proArgument = _deliberate.getArgument(debateId, proArgumentId);
        assertEq(proArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(proArgument.pro, 5);
        assertEq(proArgument.con, 5);
        assertEq(proArgument.votes, 10);
        assertEq(proArgument.fees, 0);

        assertEq(proArgument.creator, address(this));
        // A fresh argument is a draft: its finalization time is one locking window out.
        assertEq(proArgument.finalizationTime, uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION);

        assertEq(proArgument.isSupporting, true);
        assertEq(proArgument.parentArgumentId, 0);
        assertEq(proArgument.subtreeVotes, 0);

        uint16[] memory leafArgumentIds = _deliberate.getLeafArgumentIds(debateId);
        assertEq(leafArgumentIds.length, 1);
        assertEq(leafArgumentIds[0], proArgumentId);
    }

    function test_addArgument_addsAConArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 conArgumentId = _addArgument(debateId, false, 50);

        Argument.Data memory conArgument = _deliberate.getArgument(debateId, conArgumentId);
        assertEq(conArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(conArgument.pro, 5);
        assertEq(conArgument.con, 5);
        assertEq(conArgument.votes, 10);
        assertEq(conArgument.fees, 0);

        assertEq(conArgument.creator, address(this));
        // A fresh argument is a draft: its finalization time is one locking window out.
        assertEq(conArgument.finalizationTime, uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION);

        assertEq(conArgument.isSupporting, false);
        assertEq(conArgument.parentArgumentId, 0);
        assertEq(conArgument.subtreeVotes, 0);

        uint16[] memory leafArgumentIds = _deliberate.getLeafArgumentIds(debateId);
        assertEq(leafArgumentIds.length, 1);
        assertEq(leafArgumentIds[0], conArgumentId);
    }

    function test_addArgument_revertsForInitialApprovalsBelow50() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint32 initialApproval = 49;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, uint32(50), initialApproval)
        );
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_revertsForInitialApprovalsAbove99() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // 100 would empty the pro reserve and freeze the market.
        uint32 initialApproval = 100;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, uint32(99), initialApproval)
        );
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf50() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 50));
        assertEq(argument.pro, 5);
        assertEq(argument.con, 5);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf80() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // Approval is the pro-share price: 80% approval means a scarce pro reserve.
        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 80));
        assertEq(argument.pro, 2);
        assertEq(argument.con, 8);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf95() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 95));
        assertEq(argument.pro, 1);
        assertEq(argument.con, 9);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_addsTheDepositToTheParentWeightAndDebateTotal() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, true, 50);
        _addArgument(debateId, false, 50);

        // Stake weights are tally-time state; only the debate total is maintained on the way in.
        assertEq(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).subtreeVotes, 0);

        (uint32 totalVotes,,,) = _deliberate.debates(debateId);
        assertEq(totalVotes, 20);
    }

    function test_addArgument_stakesTheChosenDeposit() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // The creator stakes 40 (above the minimum) at 50% approval: the deposit splits evenly
        // into the reserves, seeds the votes, and counts in full toward the parent and debate totals.
        uint16 argumentId = _addArgument(debateId, true, 50, 40);
        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 20);
        assertEq(argument.con, 20);
        assertEq(argument.votes, 40);

        (uint32 totalVotes,,,) = _deliberate.debates(debateId);
        assertEq(totalVotes, 40);
        assertEq(_deliberate.getUserTokens(debateId, address(this)), Parameters.INITIAL_TOKENS - 40);
    }

    function test_addArgument_revertsForADepositBelowTheMinimum() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint32 deposit = Parameters._MIN_DEBATE_DEPOSIT - 1;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.DepositBelowMinimum.selector, Parameters._MIN_DEBATE_DEPOSIT, deposit)
        );
        _addArgument(debateId, true, 50, deposit);
    }

    function test_addArgument_revertsWhenTheDepositExceedsTheBalance() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint32 deposit = Parameters.INITIAL_TOKENS + 1;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.InsufficientVoteTokens.selector, deposit, Parameters.INITIAL_TOKENS)
        );
        _addArgument(debateId, true, 50, deposit);
    }

    function test_addArgument_revertsOutsideTheEditingPhase() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _endEditing(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Editing, Phase.Status.Rating)
        );
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_revertsWhenTheArgumentLimitIsReached() public {
        uint256 debateId = _createDebate();
        _fillDebateToTheArgumentCap(debateId);
        _join(debateId);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentLimitReached.selector, Parameters.MAX_ARGUMENTS));
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_keepsTheLeavesConsistentAcrossSiblingAdds() public {
        // Regression: removing the parent from the leaf list searched an unsorted array by bisection and,
        // on a miss, silently removed the last element - adding a second child to the same parent
        // dropped an unrelated leaf (and with it the subtree the tally would start from).
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        uint16 argumentB = _addArgument(debateId, false, 50);
        uint16 argumentC = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        uint16 argumentD = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: false,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });

        uint16[] memory expectedIds = new uint16[](3);
        expectedIds[0] = argumentB;
        expectedIds[1] = argumentC;
        expectedIds[2] = argumentD;
        _assertLeafSet(debateId, expectedIds);
    }

    // --- moveArgument ---

    function test_moveArgument_updatesTheLeaves() public {
        // The new parent must stop being a leaf, and the old parent - childless again - must return to being one.
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        uint16 argumentB = _addArgument(debateId, false, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);

        uint16 argumentC = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });

        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentC, newParentArgumentId: argumentB, initialApproval: 50
        });

        uint16[] memory expectedIds = new uint16[](2);
        expectedIds[0] = argumentA;
        expectedIds[1] = argumentC;
        _assertLeafSet(debateId, expectedIds);
    }

    function test_moveArgument_movesTheVoteWeightBetweenParents() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        uint16 childArgumentId = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        assertEq(_deliberate.getArgument(debateId, childArgumentId).parentArgumentId, parentArgumentId);

        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: _ROOT_ARGUMENT_ID, initialApproval: 50
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).parentArgumentId, _ROOT_ARGUMENT_ID);
    }

    function test_moveArgument_reseedsTheMarketAtTheNewApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        // A draft seeded at 50% approval: reserves split the deposit evenly.
        uint16 childArgumentId = _addArgument(debateId, true, 50);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 5);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 5);

        // Moving it re-seeds the market at 80%: con takes 80% of the (unchanged) deposit.
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 80
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 2);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 8);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).votes, 10); // the deposit is unchanged
    }

    function test_moveArgument_reseedsFromTheArgumentDeposit() public {
        // A non-default deposit must re-seed from the argument's own votes, not a fixed constant.
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        // A draft seeded with a 40-token deposit at 50%: reserves 20/20.
        uint16 childArgumentId = _addArgument(debateId, true, 50, 40);

        // Moving it re-seeds at 80% from the 40-token deposit: con takes 80% (32), pro the rest (8).
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 80
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 8);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 32);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).votes, 40);
    }

    function test_moveArgument_revertsForAnApprovalOutOfBounds() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        uint16 childArgumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, 99, 100));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 100
        });
    }

    function test_moveArgument_revertsForANonFinalNewParent() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        uint16 argumentB = _addArgument(debateId, false, 50); // a draft, so not a valid parent

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentB));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentA, newParentArgumentId: argumentB, initialApproval: 50
        });
    }

    function test_moveArgument_revertsWhenMovedUnderItself() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        // The argument being moved is necessarily a draft, never final - it cannot be its own final parent.
        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentId));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: argumentId, initialApproval: 50
        });
    }

    function test_moveArgument_revertsForANonexistentNewParent() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, uint16(42)));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: 42, initialApproval: 50
        });
    }

    // --- alterArgument ---

    function test_alterArgument_revertsForANonCreator() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        address intruder = makeAddr("intruder");
        vm.expectRevert(abi.encodeWithSelector(Deliberate.AddressInvalid.selector, address(this), intruder));
        vm.prank(intruder);
        _deliberate.alterArgument(debateId, argumentId, "A hijacked idea.");
    }

    function test_alterArgument_revertsOnceTheArgumentIsFinal() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        // The draft locks in exactly when its editing window elapses.
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION);
        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotDraft.selector, argumentId));
        _deliberate.alterArgument(debateId, argumentId, "Too late.");
    }

    function test_alterArgument_revertsWhenTheNewWindowWouldOutliveEditing() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // Added this late, the draft finalizes past the editing end - which adding allows, but
        // re-arming the window on an edit does not.
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);
        vm.warp(editingEndTime - _LOCKING_DURATION / 2);
        uint16 argumentId = _addArgument(debateId, true, 50);

        uint48 rearmedTime = uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION;
        vm.expectRevert(abi.encodeWithSelector(Deliberate.TimeOutOfBounds.selector, editingEndTime, rearmedTime));
        _deliberate.alterArgument(debateId, argumentId, "Re-armed.");
    }

    // --- stakePro / stakeCon ---

    function test_stakePro_buysProSharesAndRaisesTheApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        _deliberate.stakePro(debateId, argumentId, 20);

        // 100 initial - 10 deposit - 20 staked
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 70);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        User.Shares memory shares = _deliberate.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.pro, 22);
        assertEq(shares.con, 0);

        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 2);
        assertEq(argument.con, 24); // approval con/(pro+con) rose from 50% to 24/26 = 92.3%
        assertEq(argument.votes, 29); // 10 deposit + 20 staked - 1 fee
        assertEq(argument.fees, 1); // 5% of 20
    }

    function test_stakeCon_buysConSharesAndLowersTheApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        _deliberate.stakeCon(debateId, argumentId, 20);

        // fee 1, net 19: pro 5+19=24, con ceil(25/24)=2, shares out 22
        User.Shares memory shares = _deliberate.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.con, 22);
        assertEq(shares.pro, 0);

        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 24);
        assertEq(argument.con, 2); // approval fell from 50% to 2/26 = 7.7% - rated as bad
    }

    /// @dev Pins the market's defining behavior: buying a side always moves the approval - the
    /// price of belief, con/(pro+con) - toward that side, never away from it. Compared through
    /// cross-multiplication to avoid integer division.
    function testFuzz_stake_movesTheApprovalTowardTheBoughtSide(uint32 initialApproval, bool isPro, uint32 amount)
        public
    {
        initialApproval = uint32(bound(initialApproval, 50, 99));
        amount = uint32(bound(amount, 1, 100));

        uint256 debateId = _createDebate();
        _join(debateId);
        uint16 argumentId = _addArgument(debateId, true, initialApproval);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        Argument.Data memory before = _deliberate.getArgument(debateId, argumentId);

        address staker = makeAddr("staker");
        vm.startPrank(staker);
        _deliberate.join(debateId);
        if (isPro) {
            _deliberate.stakePro(debateId, argumentId, amount);
        } else {
            _deliberate.stakeCon(debateId, argumentId, amount);
        }
        vm.stopPrank();

        Argument.Data memory afterwards = _deliberate.getArgument(debateId, argumentId);

        // Neither reserve can ever be drained.
        assertGe(afterwards.pro, 1);
        assertGe(afterwards.con, 1);

        // newApproval >= oldApproval for pro buys (and mirrored for con buys), cross-multiplied.
        uint256 newApprovalCross = uint256(afterwards.con) * (uint256(before.pro) + uint256(before.con));
        uint256 oldApprovalCross = uint256(before.con) * (uint256(afterwards.pro) + uint256(afterwards.con));
        if (isPro) {
            assertGe(newApprovalCross, oldApprovalCross);
        } else {
            assertLe(newApprovalCross, oldApprovalCross);
        }
    }

    /// @dev Redemption can never pay out more than the market's collateral, whatever is traded.
    function testFuzz_redeem_staysWithinTheMarketCollateral(
        uint32 initialApproval,
        bool firstIsPro,
        uint32 firstAmount,
        bool secondIsPro,
        uint32 secondAmount
    ) public {
        initialApproval = uint32(bound(initialApproval, 50, 99));
        firstAmount = uint32(bound(firstAmount, 1, 100));
        secondAmount = uint32(bound(secondAmount, 1, 100));

        uint256 debateId = _createDebate();
        _join(debateId);
        uint16 argumentId = _addArgument(debateId, true, initialApproval);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        address firstStaker = makeAddr("firstStaker");
        address secondStaker = makeAddr("secondStaker");

        vm.startPrank(firstStaker);
        _deliberate.join(debateId);
        if (firstIsPro) _deliberate.stakePro(debateId, argumentId, firstAmount);
        else _deliberate.stakeCon(debateId, argumentId, firstAmount);
        vm.stopPrank();

        vm.startPrank(secondStaker);
        _deliberate.join(debateId);
        if (secondIsPro) _deliberate.stakePro(debateId, argumentId, secondAmount);
        else _deliberate.stakeCon(debateId, argumentId, secondAmount);
        vm.stopPrank();

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        uint32 collateral = _deliberate.getArgument(debateId, argumentId).votes;
        uint32 firstBefore = _deliberate.getUserTokens(debateId, firstStaker);
        uint32 secondBefore = _deliberate.getUserTokens(debateId, secondStaker);

        _deliberate.redeemArgumentShares(debateId, argumentId, firstStaker);
        _deliberate.redeemArgumentShares(debateId, argumentId, secondStaker);

        uint256 paidOut = (uint256(_deliberate.getUserTokens(debateId, firstStaker)) - firstBefore)
            + (uint256(_deliberate.getUserTokens(debateId, secondStaker)) - secondBefore);
        assertLe(paidOut, uint256(collateral));
    }

    function test_stakePro_revertsForInsufficientVoteTokens() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endEditing(debateId);

        uint32 balance = _deliberate.getUserTokens(debateId, address(this));
        vm.expectRevert(abi.encodeWithSelector(Deliberate.InsufficientVoteTokens.selector, balance + 1, balance));
        _deliberate.stakePro(debateId, argumentId, balance + 1);
    }

    function test_stakePro_revertsForTheThesis() public {
        uint256 debateId = _createDebate();
        _join(debateId);
        _endEditing(debateId);

        // The thesis is Final from creation but has no market of its own.
        vm.expectRevert(Deliberate.ThesisHasNoMarket.selector);
        _deliberate.stakePro(debateId, _ROOT_ARGUMENT_ID, 10);
    }

    function test_stakePro_revertsForANonFinalArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // Add an argument late in the editing window so it is still a draft once rating begins: its
        // finalization time (one locking window out) lands after the editing deadline.
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);
        vm.warp(editingEndTime - 1);
        uint16 argumentId = _addArgument(debateId, true, 50);
        _endEditing(debateId); // now in rating, but the argument's window has not closed yet

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentId));
        _deliberate.stakePro(debateId, argumentId, 10);
    }

    function test_stakeCon_revertsForANonexistentArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);
        _endEditing(debateId);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, uint16(42)));
        _deliberate.stakeCon(debateId, 42, 10);
    }

    // --- tallyTree ---

    function test_tallyTree_finishesTheDebate() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        _deliberate.tallyTree(debateId);

        (Phase.Status currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));
    }

    function test_tallyTree_talliesASupportingArgumentIntoAPositiveOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, true, 80);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertGt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertTrue(_deliberate.outcome(debateId));
    }

    function test_tallyTree_talliesAnOpposingArgumentIntoANegativeOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, false, 80);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertLt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertFalse(_deliberate.outcome(debateId));
    }

    function test_tallyTree_staysWithinTheBlockGasLimitAtTheArgumentCap() public {
        uint256 debateId = _createDebate();
        _fillDebateToTheArgumentCap(debateId);

        // By the Tallying phase every argument is final (each editing window elapsed), so all of them carry
        // impact - the expensive path this benchmark must stay within block gas for.
        _endRating(debateId);

        uint256 gasBefore = gasleft();
        _deliberate.tallyTree(debateId);
        uint256 gasUsed = gasBefore - gasleft();

        // The tally is atomic, so the maximally-sized tree must fit within a mainnet block (~36M today).
        assertLt(gasUsed, 30_000_000);
    }

    function test_tallyTree_finalizesArgumentsByTime() public {
        // No explicit finalize step: an argument left untouched becomes final once its editing window elapses
        // (by the Tallying phase, always), so it is tallied automatically.
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, true, 95); // supporting, seeded high; never touched again
        _endRating(debateId);

        _deliberate.tallyTree(debateId);

        assertGt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertTrue(_deliberate.outcome(debateId));
    }

    function test_tallyTree_talliesRecursivelyUpTheTree() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: argumentId,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: false,
            initialApproval: 95,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // The fully-approved opposing child weakens its parent from below ...
        assertLt(_deliberate.getArgument(debateId, argumentId).descendantsImpact, 0);
        // ... and every argument ends up tallied.
        assertEq(_deliberate.getArgument(debateId, argumentId).untalliedChilds, 0);
        assertEq(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).untalliedChilds, 0);
    }

    // --- outcome ---

    function test_outcome_revertsBeforeTheTallyHasRun() public {
        uint256 debateId = _createDebate();

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Editing)
        );
        _deliberate.outcome(debateId);

        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _deliberate.outcome(debateId);
    }

    function test_outcome_returnsTheOutcomeOnceTheDebateIsFinished() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        _deliberate.tallyTree(debateId);

        assertEq(_deliberate.outcome(debateId), false);
    }

    // --- redeemArgumentShares ---

    function test_redeemArgumentShares_revertsBeforeTheTallyHasRun() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _deliberate.redeemArgumentShares(debateId, _ROOT_ARGUMENT_ID, address(this));
    }

    function test_redeemArgumentShares_succeedsOnceTheDebateIsFinished() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        _deliberate.redeemArgumentShares(debateId, _ROOT_ARGUMENT_ID, address(this));

        assertEq(_deliberate.getUserTokens(debateId, address(this)), 0);
    }

    function test_redeemArgumentShares_paysTheEarlyCorrectStakerAProfit() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        address earlyStaker = makeAddr("earlyStaker");
        address lateStaker = makeAddr("lateStaker");

        // The early staker buys pro cheap at 50% approval: 13 shares for 10 tokens (-> 88.2%).
        vm.startPrank(earlyStaker);
        _deliberate.join(debateId);
        _deliberate.stakePro(debateId, argumentId, 10);
        vm.stopPrank();

        // The crowd confirms the rating later, at a higher price: 20 shares for 20 tokens (-> 97.1%).
        vm.startPrank(lateStaker);
        _deliberate.join(debateId);
        _deliberate.stakePro(debateId, argumentId, 20);
        vm.stopPrank();

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        _deliberate.redeemArgumentShares(debateId, argumentId, earlyStaker);
        _deliberate.redeemArgumentShares(debateId, argumentId, lateStaker);

        // Early: 13 shares x 34/35 = 12 tokens back on 10 staked - correcting the rating early pays.
        assertEq(_deliberate.getUserTokens(debateId, earlyStaker), 102);
        // Late: 20 shares x 34/35 = 19 tokens back on 20 staked - fee and slippage eat the late trade.
        assertEq(_deliberate.getUserTokens(debateId, lateStaker), 99);
        // Solvency: 12 + 19 paid out of the market's 39 collateral tokens.
    }

    // --- redeemArgumentSharesBatch ---

    function test_redeemArgumentSharesBatch_redeemsAcrossArguments() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argument1 = _addArgument(debateId, true, 50); // reserves 5/5
        uint16 argument2 = _addArgument(debateId, true, 50); // reserves 5/5
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        // One staker takes a con position in both arguments (22 con shares each).
        address staker = makeAddr("staker");
        vm.startPrank(staker);
        _deliberate.join(debateId);
        _deliberate.stakeCon(debateId, argument1, 20);
        _deliberate.stakeCon(debateId, argument2, 20);
        vm.stopPrank();
        assertEq(_deliberate.getUserTokens(debateId, staker), 60); // 100 - 20 - 20

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        uint16[] memory argumentIds = new uint16[](2);
        argumentIds[0] = argument1;
        argumentIds[1] = argument2;
        _deliberate.redeemArgumentSharesBatch(debateId, argumentIds, staker);

        // Both positions redeemed in one call: 20 tokens back per argument.
        assertEq(_deliberate.getUserShares(debateId, argument1, staker).con, 0);
        assertEq(_deliberate.getUserShares(debateId, argument2, staker).con, 0);
        assertEq(_deliberate.getUserTokens(debateId, staker), 100); // 60 + 20 + 20
    }

    function test_redeemArgumentSharesBatch_skipsArgumentsWithoutShares() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argument1 = _addArgument(debateId, true, 50);
        uint16 argument2 = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        // The staker only holds shares in argument1.
        address staker = makeAddr("staker");
        vm.startPrank(staker);
        _deliberate.join(debateId);
        _deliberate.stakeCon(debateId, argument1, 20);
        vm.stopPrank();

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // The batch includes argument2, which the staker never staked on: it is skipped, not reverted.
        uint16[] memory argumentIds = new uint16[](2);
        argumentIds[0] = argument1;
        argumentIds[1] = argument2;
        _deliberate.redeemArgumentSharesBatch(debateId, argumentIds, staker);

        assertEq(_deliberate.getUserShares(debateId, argument1, staker).con, 0);
        assertEq(_deliberate.getUserTokens(debateId, staker), 100); // 100 - 20 + 20; argument2 a no-op
    }

    function test_redeemArgumentSharesBatch_revertsBeforeTheTallyHasRun() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        uint16[] memory argumentIds = new uint16[](1);
        argumentIds[0] = _ROOT_ARGUMENT_ID;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _deliberate.redeemArgumentSharesBatch(debateId, argumentIds, address(this));
    }

    // --- claimFees ---

    function test_claimFees_creditsTheAccruedFeesToTheArgumentCreator() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        // A second participant stakes 20; the 5% fee (1 token) accrues to the argument.
        address staker = makeAddr("staker");
        vm.prank(staker);
        _deliberate.join(debateId);
        vm.prank(staker);
        _deliberate.stakePro(debateId, argumentId, 20);

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertEq(_deliberate.getUserTokens(debateId, address(this)), 90); // 100 - 10 deposit

        _deliberate.claimFees(debateId, argumentId);

        assertEq(_deliberate.getUserTokens(debateId, address(this)), 91); // + 1 fee
        assertEq(_deliberate.getArgument(debateId, argumentId).fees, 0);

        // A second claim is a no-op.
        _deliberate.claimFees(debateId, argumentId);
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 91);
    }

    function test_claimFees_revertsWhileTheDebateIsNotFinished() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _deliberate.claimFees(debateId, argumentId);
    }

    // --- events ---
    // Every state transition emits an event carrying the resulting state, so an indexer can
    // mirror the debate without reading the contract (and without redoing the market rounding).

    function test_createDebate_emitsDebateCreated() public {
        uint48 creationTime = uint48(vm.getBlockTimestamp());

        vm.expectEmit();
        emit IDeliberate.DebateCreated({
            debateId: 0,
            creator: address(this),
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingEndTime: creationTime + 7 * _LOCKING_DURATION,
            ratingEndTime: creationTime + 10 * _LOCKING_DURATION,
            feePercentage: 5
        });
        _createDebate();
    }

    function test_join_emitsJoined() public {
        uint256 debateId = _createDebate();

        vm.expectEmit();
        emit IDeliberate.Joined({debateId: debateId, account: address(this), tokens: Parameters.INITIAL_TOKENS});
        _join(debateId);
    }

    function test_addArgument_emitsArgumentAddedWithTheSeededMarket() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // An 80% initial approval seeds a scarce pro reserve: 2 pro / 8 con.
        vm.expectEmit();
        emit IDeliberate.ArgumentAdded({
            debateId: debateId,
            argumentId: 1,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            creator: address(this),
            isSupporting: true,
            contentURI: _PRO_ARGUMENT_CONTENT,
            pro: 2,
            con: 8,
            finalizationTime: uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION
        });
        _addArgument(debateId, true, 80);
    }

    function test_moveArgument_emitsArgumentMoved() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 newParentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        uint16 movedArgumentId = _addArgument(debateId, false, 50);

        vm.expectEmit();
        emit IDeliberate.ArgumentMoved({
            debateId: debateId,
            argumentId: movedArgumentId,
            newParentArgumentId: newParentArgumentId,
            oldParentArgumentId: _ROOT_ARGUMENT_ID,
            pro: 2,
            con: 8
        });
        _deliberate.moveArgument({
            debateId: debateId,
            argumentId: movedArgumentId,
            newParentArgumentId: newParentArgumentId,
            initialApproval: 80
        });
    }

    function test_alterArgument_emitsArgumentAltered() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        bytes32 newContentURI = "An even better idea.";

        vm.expectEmit();
        emit IDeliberate.ArgumentAltered({
            debateId: debateId,
            argumentId: argumentId,
            contentURI: newContentURI,
            finalizationTime: uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION
        });
        _deliberate.alterArgument(debateId, argumentId, newContentURI);
    }

    function test_stakePro_emitsStaked() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        vm.expectEmit();
        emit IDeliberate.Staked({
            debateId: debateId,
            argumentId: argumentId,
            staker: address(this),
            data: Argument.Stake({isPro: true, voteTokensStaked: 20, fee: 1, sharesOut: 22})
        });
        _deliberate.stakePro(debateId, argumentId, 20);
    }

    function test_tallyTree_emitsDebateFinishedWithTheOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, true, 80); // a supporting argument rated well, finalized by time at the tally
        _endRating(debateId);

        vm.expectEmit();
        emit IDeliberate.DebateFinished({debateId: debateId, approved: true});
        _deliberate.tallyTree(debateId);
    }

    function test_redeemArgumentShares_emitsSharesRedeemed() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80); // reserves 2/8
        vm.warp(vm.getBlockTimestamp() + _LOCKING_DURATION + 1);
        _endEditing(debateId);

        // fee 1, net 19: pro 2+19=21, con ceil(16/21)=1, shares out 8+19-1=26
        _deliberate.stakeCon(debateId, argumentId, 20);

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // 26 con shares x 21/22 of the market, rounded down: 24 tokens.
        vm.expectEmit();
        emit IDeliberate.SharesRedeemed({
            debateId: debateId, argumentId: argumentId, account: address(this), proShares: 0, conShares: 26, payout: 24
        });
        _deliberate.redeemArgumentShares(debateId, argumentId, address(this));
    }

    function test_redeemArgumentShares_emitsNothingWithoutShares() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        vm.recordLogs();
        _deliberate.redeemArgumentShares(debateId, argumentId, makeAddr("uninvolved"));

        assertEq(vm.getRecordedLogs().length, 0);
    }
}
