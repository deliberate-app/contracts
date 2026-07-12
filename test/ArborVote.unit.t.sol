// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IArborVote} from "../src/interfaces/IArborVote.sol";
import {Argument} from "../src/libs/Argument.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {User} from "../src/libs/User.sol";
import {MockProofOfHumanity} from "./mocks/MockProofOfHumanity.m.sol";

contract ArborVoteTest is Test {
    ArborVote internal _arborVote;

    MockProofOfHumanity internal _mockProofOfHumanity;

    uint48 internal constant _TIME_UNIT = 1 * 60; // 1 minute
    bytes32 internal constant _THESIS_CONTENT = "We should do XYZ";
    bytes32 internal constant _PRO_ARGUMENT_CONTENT = "This is a good idea.";
    uint16 internal constant _ROOT_ARGUMENT_ID = 0;

    function setUp() public {
        _mockProofOfHumanity = new MockProofOfHumanity();
        _arborVote = new ArborVote(_mockProofOfHumanity);
    }

    // --- helpers ---

    function _createDebate() internal returns (uint256 debateId) {
        debateId = _arborVote.createDebate(_THESIS_CONTENT, _TIME_UNIT);
    }

    function _join(uint256 debateId) internal {
        _arborVote.join(debateId);
    }

    function _addArgument(uint256 debateId, bool isSupporting, uint32 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: isSupporting,
            initialApproval: initialApproval
        });
    }

    function _assertLeafSet(uint256 debateId, uint16[] memory expectedIds) internal view {
        uint16[] memory actualIds = _arborVote.getLeafArgumentIds(debateId);
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
            _arborVote.join(debateId);
            // Each participant's budget affords ten argument deposits.
            for (uint256 i = 0; i < 10 && added < maxArguments - 1; i++) {
                _arborVote.addArgument({
                    debateId: debateId,
                    parentArgumentId: _ROOT_ARGUMENT_ID,
                    contentURI: _PRO_ARGUMENT_CONTENT,
                    isSupporting: added % 2 == 0,
                    initialApproval: 50
                });
                added++;
            }
            vm.stopPrank();
            participantIndex++;
        }
    }

    function _endEditing(uint256 debateId) internal {
        (, uint48 editingEndTime,,) = _arborVote.phases(debateId);
        vm.warp(editingEndTime + 1);
        _arborVote.advancePhase(debateId);
    }

    function _endRating(uint256 debateId) internal {
        (,, uint48 ratingEndTime,) = _arborVote.phases(debateId);
        vm.warp(ratingEndTime + 1);
        _arborVote.advancePhase(debateId);
    }

    // --- advancePhase ---

    function test_advancePhase_revertsForAnUninitializedDebate() public {
        _createDebate();

        uint256 uninitializedDebateId = 123;
        (Phase.Status currentPhase,,,) = _arborVote.phases(uninitializedDebateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Uninitialized));

        vm.expectRevert(abi.encodeWithSelector(ArborVote.DebateUninitialized.selector, uninitializedDebateId));
        _arborVote.advancePhase(uninitializedDebateId);
    }

    function test_advancePhase_advancesThePhasesAfterTheTimeHasPassed() public {
        uint256 debateId = _createDebate();

        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));

        vm.warp(editingEndTime + 1);
        _arborVote.advancePhase(debateId);
        (currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Rating));

        vm.warp(ratingEndTime + 1);
        _arborVote.advancePhase(debateId);
        (currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Tallying));
    }

    function test_advancePhase_isIdempotentAfterRatingHasEnded() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        _arborVote.advancePhase(debateId);

        (Phase.Status currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Tallying));
    }

    function test_advancePhase_doesNotLeaveTheFinishedPhase() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        _arborVote.advancePhase(debateId);

        (Phase.Status currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));
    }

    // --- createDebate ---

    function test_createDebate_isUninitializedBeforeADebateIsCreated() public view {
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 timeUnit) = _arborVote.phases(0);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Uninitialized));
        assertEq(editingEndTime, 0);
        assertEq(ratingEndTime, 0);
        assertEq(timeUnit, 0);
    }

    function test_createDebate_incrementsTheDebateId() public {
        uint256 debateId = _arborVote.createDebate(_THESIS_CONTENT, _TIME_UNIT);
        assertEq(debateId, 0);

        debateId = _arborVote.createDebate(_THESIS_CONTENT, _TIME_UNIT);
        assertEq(debateId, 1);
    }

    function test_debatesCount_countsCreatedDebates() public {
        assertEq(_arborVote.debatesCount(), 0);

        _arborVote.createDebate(_THESIS_CONTENT, _TIME_UNIT);
        assertEq(_arborVote.debatesCount(), 1);

        _arborVote.createDebate(_THESIS_CONTENT, _TIME_UNIT);
        assertEq(_arborVote.debatesCount(), 2);
    }

    function test_createDebate_initializesThePhaseData() public {
        uint256 debateId = _createDebate();

        uint256 currentTime = vm.getBlockTimestamp();
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 ratingEndTime, uint48 timeUnit) =
            _arborVote.phases(debateId);

        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));
        assertEq(timeUnit, _TIME_UNIT);
        assertEq(editingEndTime, currentTime + 7 * _TIME_UNIT);
        assertEq(ratingEndTime, currentTime + 10 * _TIME_UNIT);
    }

    function test_createDebate_initializesTheRootArgument() public {
        uint256 debateId = _createDebate();

        Argument.Data memory rootArgument = _arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID);
        assertEq(rootArgument.contentURI, _THESIS_CONTENT);

        assertEq(rootArgument.pro, 0);
        assertEq(rootArgument.con, 0);
        assertEq(rootArgument.votes, 0);
        assertEq(rootArgument.fees, 0);

        assertEq(rootArgument.creator, address(this));
        assertEq(uint256(rootArgument.state), uint256(Argument.State.Final));
        assertEq(rootArgument.finalizationTime, uint48(vm.getBlockTimestamp()));

        assertEq(rootArgument.isSupporting, false);
        assertEq(rootArgument.parentArgumentId, 0);
        assertEq(rootArgument.childsVote, 0);

        assertEq(_arborVote.getLeafArgumentIds(debateId).length, 0);
    }

    // --- join ---

    function test_join_joinsADebate() public {
        uint256 debateId = _createDebate();

        assertEq(uint256(_arborVote.getUserRole(debateId, address(this))), uint256(User.Role.Unassigned));
        assertEq(_arborVote.getUserTokens(debateId, address(this)), 0);

        User.Shares memory shares = _arborVote.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);

        _join(debateId);

        assertEq(uint256(_arborVote.getUserRole(debateId, address(this))), uint256(User.Role.Participant));
        assertEq(_arborVote.getUserTokens(debateId, address(this)), Parameters.INITIAL_TOKENS);

        shares = _arborVote.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);
    }

    function test_join_revertsIfTheUserHasNoValidIdentityProof() public {
        uint256 debateId = _createDebate();

        _mockProofOfHumanity.deny(address(this));

        vm.expectRevert(ArborVote.IdentityProofInvalid.selector);
        _arborVote.join(debateId);
    }

    function test_join_succeedsDuringTheRatingPhase() public {
        uint256 debateId = _createDebate();
        _endEditing(debateId);

        _join(debateId);

        assertEq(uint256(_arborVote.getUserRole(debateId, address(this))), uint256(User.Role.Participant));
    }

    function test_join_revertsForAnUninitializedDebate() public {
        uint256 uninitializedDebateId = 123;

        vm.expectRevert(abi.encodeWithSelector(ArborVote.DebateUninitialized.selector, uninitializedDebateId));
        _arborVote.join(uninitializedDebateId);
    }

    function test_join_revertsOnceRatingHasEnded() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseExceeded.selector, Phase.Status.Rating, Phase.Status.Tallying)
        );
        _arborVote.join(debateId);

        _arborVote.tallyTree(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseExceeded.selector, Phase.Status.Rating, Phase.Status.Finished)
        );
        _arborVote.join(debateId);
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

        Argument.Data memory proArgument = _arborVote.getArgument(debateId, proArgumentId);
        assertEq(proArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(proArgument.pro, 5);
        assertEq(proArgument.con, 5);
        assertEq(proArgument.votes, 10);
        assertEq(proArgument.fees, 0);

        assertEq(proArgument.creator, address(this));
        assertEq(uint256(proArgument.state), uint256(Argument.State.Created));
        assertEq(proArgument.finalizationTime, uint48(vm.getBlockTimestamp()) + _TIME_UNIT);

        assertEq(proArgument.isSupporting, true);
        assertEq(proArgument.parentArgumentId, 0);
        assertEq(proArgument.childsVote, 0);

        uint16[] memory leafArgumentIds = _arborVote.getLeafArgumentIds(debateId);
        assertEq(leafArgumentIds.length, 1);
        assertEq(leafArgumentIds[0], proArgumentId);
    }

    function test_addArgument_addsAConArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 conArgumentId = _addArgument(debateId, false, 50);

        Argument.Data memory conArgument = _arborVote.getArgument(debateId, conArgumentId);
        assertEq(conArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(conArgument.pro, 5);
        assertEq(conArgument.con, 5);
        assertEq(conArgument.votes, 10);
        assertEq(conArgument.fees, 0);

        assertEq(conArgument.creator, address(this));
        assertEq(uint256(conArgument.state), uint256(Argument.State.Created));
        assertEq(conArgument.finalizationTime, uint48(vm.getBlockTimestamp()) + _TIME_UNIT);

        assertEq(conArgument.isSupporting, false);
        assertEq(conArgument.parentArgumentId, 0);
        assertEq(conArgument.childsVote, 0);

        uint16[] memory leafArgumentIds = _arborVote.getLeafArgumentIds(debateId);
        assertEq(leafArgumentIds.length, 1);
        assertEq(leafArgumentIds[0], conArgumentId);
    }

    function test_addArgument_revertsForInitialApprovalsBelow50() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint32 initialApproval = 49;
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.InitialApprovalOutOfBounds.selector, uint32(50), initialApproval)
        );
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_revertsForInitialApprovalsAbove99() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // 100 would empty the pro reserve and freeze the market.
        uint32 initialApproval = 100;
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.InitialApprovalOutOfBounds.selector, uint32(99), initialApproval)
        );
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf50() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 50));
        assertEq(argument.pro, 5);
        assertEq(argument.con, 5);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf80() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // Approval is the pro-share price: 80% approval means a scarce pro reserve.
        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 80));
        assertEq(argument.pro, 2);
        assertEq(argument.con, 8);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf95() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 95));
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

        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsVote, 20);

        (uint32 totalVotes,) = _arborVote.debates(debateId);
        assertEq(totalVotes, 20);
    }

    function test_addArgument_revertsOutsideTheEditingPhase() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _endEditing(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Editing, Phase.Status.Rating)
        );
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_revertsWhenTheArgumentLimitIsReached() public {
        uint256 debateId = _createDebate();
        _fillDebateToTheArgumentCap(debateId);
        _join(debateId);

        vm.expectRevert(abi.encodeWithSelector(ArborVote.ArgumentLimitReached.selector, Parameters.MAX_ARGUMENTS));
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_keepsTheLeavesConsistentAcrossSiblingAdds() public {
        // Regression: removing the parent from the leaf list searched an unsorted array by bisection and,
        // on a miss, silently removed the last element - adding a second child to the same parent
        // dropped an unrelated leaf (and with it the subtree the tally would start from).
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentA);

        uint16 argumentB = _addArgument(debateId, false, 50);
        uint16 argumentC = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50
        });
        uint16 argumentD = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: false,
            initialApproval: 50
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
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentA);
        _arborVote.finalizeArgument(debateId, argumentB);

        uint16 argumentC = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: argumentA,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50
        });

        _arborVote.moveArgument({
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
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, parentArgumentId);

        uint16 childArgumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: true,
            initialApproval: 50
        });
        assertEq(_arborVote.getArgument(debateId, parentArgumentId).childsVote, 10);
        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsVote, 10);

        _arborVote.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: _ROOT_ARGUMENT_ID, initialApproval: 50
        });

        assertEq(_arborVote.getArgument(debateId, parentArgumentId).childsVote, 0);
        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsVote, 20);
    }

    function test_moveArgument_reseedsTheMarketAtTheNewApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, parentArgumentId);

        // A draft seeded at 50% approval: reserves split the deposit evenly.
        uint16 childArgumentId = _addArgument(debateId, true, 50);
        assertEq(_arborVote.getArgument(debateId, childArgumentId).pro, 5);
        assertEq(_arborVote.getArgument(debateId, childArgumentId).con, 5);

        // Moving it re-seeds the market at 80%: con takes 80% of the (unchanged) deposit.
        _arborVote.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 80
        });

        assertEq(_arborVote.getArgument(debateId, childArgumentId).pro, 2);
        assertEq(_arborVote.getArgument(debateId, childArgumentId).con, 8);
        assertEq(_arborVote.getArgument(debateId, childArgumentId).votes, 10); // the deposit is unchanged
    }

    function test_moveArgument_revertsForAnApprovalOutOfBounds() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, parentArgumentId);

        uint16 childArgumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(abi.encodeWithSelector(ArborVote.InitialApprovalOutOfBounds.selector, 99, 100));
        _arborVote.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 100
        });
    }

    function test_moveArgument_revertsForANonFinalNewParent() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        uint16 argumentB = _addArgument(debateId, false, 50); // stays Created

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.StateInvalid.selector, Argument.State.Final, Argument.State.Created)
        );
        _arborVote.moveArgument({
            debateId: debateId, argumentId: argumentA, newParentArgumentId: argumentB, initialApproval: 50
        });
    }

    function test_moveArgument_revertsWhenMovedUnderItself() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        // The moved argument is necessarily Created, never Final - self-parenting is a state error.
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.StateInvalid.selector, Argument.State.Final, Argument.State.Created)
        );
        _arborVote.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: argumentId, initialApproval: 50
        });
    }

    function test_moveArgument_revertsForANonexistentNewParent() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.StateInvalid.selector, Argument.State.Final, Argument.State.Uninitialized)
        );
        _arborVote.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: 42, initialApproval: 50
        });
    }

    // --- stakePro / stakeCon ---

    function test_stakePro_buysProSharesAndRaisesTheApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        _arborVote.stakePro(debateId, argumentId, 20);

        // 100 initial - 10 deposit - 20 staked
        assertEq(_arborVote.getUserTokens(debateId, address(this)), 70);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        User.Shares memory shares = _arborVote.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.pro, 22);
        assertEq(shares.con, 0);

        Argument.Data memory argument = _arborVote.getArgument(debateId, argumentId);
        assertEq(argument.pro, 2);
        assertEq(argument.con, 24); // approval con/(pro+con) rose from 50% to 24/26 = 92.3%
        assertEq(argument.votes, 29); // 10 deposit + 20 staked - 1 fee
        assertEq(argument.fees, 1); // 5% of 20
    }

    function test_stakeCon_buysConSharesAndLowersTheApproval() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        _arborVote.stakeCon(debateId, argumentId, 20);

        // fee 1, net 19: pro 5+19=24, con ceil(25/24)=2, shares out 22
        User.Shares memory shares = _arborVote.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.con, 22);
        assertEq(shares.pro, 0);

        Argument.Data memory argument = _arborVote.getArgument(debateId, argumentId);
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
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        Argument.Data memory before = _arborVote.getArgument(debateId, argumentId);

        address staker = makeAddr("staker");
        vm.startPrank(staker);
        _arborVote.join(debateId);
        if (isPro) {
            _arborVote.stakePro(debateId, argumentId, amount);
        } else {
            _arborVote.stakeCon(debateId, argumentId, amount);
        }
        vm.stopPrank();

        Argument.Data memory afterwards = _arborVote.getArgument(debateId, argumentId);

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
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        address firstStaker = makeAddr("firstStaker");
        address secondStaker = makeAddr("secondStaker");

        vm.startPrank(firstStaker);
        _arborVote.join(debateId);
        if (firstIsPro) _arborVote.stakePro(debateId, argumentId, firstAmount);
        else _arborVote.stakeCon(debateId, argumentId, firstAmount);
        vm.stopPrank();

        vm.startPrank(secondStaker);
        _arborVote.join(debateId);
        if (secondIsPro) _arborVote.stakePro(debateId, argumentId, secondAmount);
        else _arborVote.stakeCon(debateId, argumentId, secondAmount);
        vm.stopPrank();

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        uint32 collateral = _arborVote.getArgument(debateId, argumentId).votes;
        uint32 firstBefore = _arborVote.getUserTokens(debateId, firstStaker);
        uint32 secondBefore = _arborVote.getUserTokens(debateId, secondStaker);

        _arborVote.redeemArgumentShares(debateId, argumentId, firstStaker);
        _arborVote.redeemArgumentShares(debateId, argumentId, secondStaker);

        uint256 paidOut = (uint256(_arborVote.getUserTokens(debateId, firstStaker)) - firstBefore)
            + (uint256(_arborVote.getUserTokens(debateId, secondStaker)) - secondBefore);
        assertLe(paidOut, uint256(collateral));
    }

    function test_stakePro_revertsForTheThesis() public {
        uint256 debateId = _createDebate();
        _join(debateId);
        _endEditing(debateId);

        // The thesis is Final from creation but has no market of its own.
        vm.expectRevert(ArborVote.ThesisHasNoMarket.selector);
        _arborVote.stakePro(debateId, _ROOT_ARGUMENT_ID, 10);
    }

    function test_stakePro_revertsForANonFinalArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // stays Created: never finalized
        _endEditing(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.StateInvalid.selector, Argument.State.Final, Argument.State.Created)
        );
        _arborVote.stakePro(debateId, argumentId, 10);
    }

    function test_stakeCon_revertsForANonexistentArgument() public {
        uint256 debateId = _createDebate();
        _join(debateId);
        _endEditing(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.StateInvalid.selector, Argument.State.Final, Argument.State.Uninitialized)
        );
        _arborVote.stakeCon(debateId, 42, 10);
    }

    // --- tallyTree ---

    function test_tallyTree_finishesTheDebate() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        _arborVote.tallyTree(debateId);

        (Phase.Status currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));
    }

    function test_tallyTree_talliesASupportingArgumentIntoAPositiveOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        assertGt(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertTrue(_arborVote.outcome(debateId));
    }

    function test_tallyTree_talliesAnOpposingArgumentIntoANegativeOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, false, 80);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        assertLt(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertFalse(_arborVote.outcome(debateId));
    }

    function test_tallyTree_staysWithinTheBlockGasLimitAtTheArgumentCap() public {
        uint256 debateId = _createDebate();
        _fillDebateToTheArgumentCap(debateId);

        // Finalize every argument so all of them carry impact (the expensive path).
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        uint16 maxArguments = Parameters.MAX_ARGUMENTS;
        for (uint16 i = 1; i < maxArguments; i++) {
            _arborVote.finalizeArgument(debateId, i);
        }

        _endRating(debateId);

        uint256 gasBefore = gasleft();
        _arborVote.tallyTree(debateId);
        uint256 gasUsed = gasBefore - gasleft();

        // The tally is atomic, so the maximally-sized tree must fit within a mainnet block (~36M today).
        assertLt(gasUsed, 30_000_000);
    }

    function test_tallyTree_ignoresUnfinalizedArguments() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        _addArgument(debateId, true, 95); // stays Created: never finalized
        _endRating(debateId);

        _arborVote.tallyTree(debateId);

        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsImpact, 0);
        assertFalse(_arborVote.outcome(debateId));
    }

    function test_tallyTree_talliesRecursivelyUpTheTree() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);

        uint16 childArgumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: argumentId,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: false,
            initialApproval: 95
        });
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, childArgumentId);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        // The fully-approved opposing child weakens its parent from below ...
        assertLt(_arborVote.getArgument(debateId, argumentId).descendantsImpact, 0);
        // ... and every argument ends up tallied.
        assertEq(_arborVote.getArgument(debateId, argumentId).untalliedChilds, 0);
        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).untalliedChilds, 0);
    }

    // --- outcome ---

    function test_outcome_revertsBeforeTheTallyHasRun() public {
        uint256 debateId = _createDebate();

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Editing)
        );
        _arborVote.outcome(debateId);

        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _arborVote.outcome(debateId);
    }

    function test_outcome_returnsTheOutcomeOnceTheDebateIsFinished() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        _arborVote.tallyTree(debateId);

        assertEq(_arborVote.outcome(debateId), false);
    }

    // --- redeemArgumentShares ---

    function test_redeemArgumentShares_revertsBeforeTheTallyHasRun() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _arborVote.redeemArgumentShares(debateId, _ROOT_ARGUMENT_ID, address(this));
    }

    function test_redeemArgumentShares_succeedsOnceTheDebateIsFinished() public {
        uint256 debateId = _createDebate();
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        _arborVote.redeemArgumentShares(debateId, _ROOT_ARGUMENT_ID, address(this));

        assertEq(_arborVote.getUserTokens(debateId, address(this)), 0);
    }

    function test_redeemArgumentShares_paysTheEarlyCorrectStakerAProfit() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5, approval 50%
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        address earlyStaker = makeAddr("earlyStaker");
        address lateStaker = makeAddr("lateStaker");

        // The early staker buys pro cheap at 50% approval: 13 shares for 10 tokens (-> 88.2%).
        vm.startPrank(earlyStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 10);
        vm.stopPrank();

        // The crowd confirms the rating later, at a higher price: 20 shares for 20 tokens (-> 97.1%).
        vm.startPrank(lateStaker);
        _arborVote.join(debateId);
        _arborVote.stakePro(debateId, argumentId, 20);
        vm.stopPrank();

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        _arborVote.redeemArgumentShares(debateId, argumentId, earlyStaker);
        _arborVote.redeemArgumentShares(debateId, argumentId, lateStaker);

        // Early: 13 shares x 34/35 = 12 tokens back on 10 staked - correcting the rating early pays.
        assertEq(_arborVote.getUserTokens(debateId, earlyStaker), 102);
        // Late: 20 shares x 34/35 = 19 tokens back on 20 staked - fee and slippage eat the late trade.
        assertEq(_arborVote.getUserTokens(debateId, lateStaker), 99);
        // Solvency: 12 + 19 paid out of the market's 39 collateral tokens.
    }

    // --- claimFees ---

    function test_claimFees_creditsTheAccruedFeesToTheArgumentCreator() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        // A second participant stakes 20; the 5% fee (1 token) accrues to the argument.
        address staker = makeAddr("staker");
        vm.prank(staker);
        _arborVote.join(debateId);
        vm.prank(staker);
        _arborVote.stakePro(debateId, argumentId, 20);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        assertEq(_arborVote.getUserTokens(debateId, address(this)), 90); // 100 - 10 deposit

        _arborVote.claimFees(debateId, argumentId);

        assertEq(_arborVote.getUserTokens(debateId, address(this)), 91); // + 1 fee
        assertEq(_arborVote.getArgument(debateId, argumentId).fees, 0);

        // A second claim is a no-op.
        _arborVote.claimFees(debateId, argumentId);
        assertEq(_arborVote.getUserTokens(debateId, address(this)), 91);
    }

    function test_claimFees_revertsWhileTheDebateIsNotFinished() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endRating(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.PhaseInvalid.selector, Phase.Status.Finished, Phase.Status.Tallying)
        );
        _arborVote.claimFees(debateId, argumentId);
    }

    // --- events ---
    // Every state transition emits an event carrying the resulting state, so an indexer can
    // mirror the debate without reading the contract (and without redoing the market rounding).

    function test_createDebate_emitsDebateCreated() public {
        uint48 creationTime = uint48(vm.getBlockTimestamp());

        vm.expectEmit();
        emit IArborVote.DebateCreated({
            debateId: 0,
            creator: address(this),
            contentURI: _THESIS_CONTENT,
            timeUnit: _TIME_UNIT,
            editingEndTime: creationTime + 7 * _TIME_UNIT,
            ratingEndTime: creationTime + 10 * _TIME_UNIT
        });
        _createDebate();
    }

    function test_join_emitsJoined() public {
        uint256 debateId = _createDebate();

        vm.expectEmit();
        emit IArborVote.Joined({debateId: debateId, account: address(this), tokens: Parameters.INITIAL_TOKENS});
        _join(debateId);
    }

    function test_addArgument_emitsArgumentAddedWithTheSeededMarket() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        // An 80% initial approval seeds a scarce pro reserve: 2 pro / 8 con.
        vm.expectEmit();
        emit IArborVote.ArgumentAdded({
            debateId: debateId,
            argumentId: 1,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            creator: address(this),
            isSupporting: true,
            contentURI: _PRO_ARGUMENT_CONTENT,
            pro: 2,
            con: 8,
            finalizationTime: uint48(vm.getBlockTimestamp()) + _TIME_UNIT
        });
        _addArgument(debateId, true, 80);
    }

    function test_moveArgument_emitsArgumentMoved() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 newParentArgumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, newParentArgumentId);

        uint16 movedArgumentId = _addArgument(debateId, false, 50);

        vm.expectEmit();
        emit IArborVote.ArgumentMoved({
            debateId: debateId,
            argumentId: movedArgumentId,
            newParentArgumentId: newParentArgumentId,
            oldParentArgumentId: _ROOT_ARGUMENT_ID,
            pro: 2,
            con: 8
        });
        _arborVote.moveArgument({
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
        emit IArborVote.ArgumentAltered({
            debateId: debateId,
            argumentId: argumentId,
            contentURI: newContentURI,
            finalizationTime: uint48(vm.getBlockTimestamp()) + _TIME_UNIT
        });
        _arborVote.alterArgument(debateId, argumentId, newContentURI);
    }

    function test_finalizeArgument_emitsArgumentFinalized() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);

        vm.expectEmit();
        emit IArborVote.ArgumentFinalized({debateId: debateId, argumentId: argumentId});
        _arborVote.finalizeArgument(debateId, argumentId);
    }

    function test_advancePhase_emitsPhaseAdvancedOnEachTransition() public {
        uint256 debateId = _createDebate();
        (, uint48 editingEndTime, uint48 ratingEndTime,) = _arborVote.phases(debateId);

        vm.warp(editingEndTime + 1);
        vm.expectEmit();
        emit IArborVote.PhaseAdvanced({debateId: debateId, newPhase: Phase.Status.Rating});
        _arborVote.advancePhase(debateId);

        vm.warp(ratingEndTime + 1);
        vm.expectEmit();
        emit IArborVote.PhaseAdvanced({debateId: debateId, newPhase: Phase.Status.Tallying});
        _arborVote.advancePhase(debateId);
    }

    function test_advancePhase_emitsNothingBelowTheTimeGates() public {
        uint256 debateId = _createDebate();

        vm.recordLogs();
        _arborVote.advancePhase(debateId);

        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_stakePro_emitsStaked() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50); // reserves 5/5
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        vm.expectEmit();
        emit IArborVote.Staked({
            debateId: debateId,
            argumentId: argumentId,
            staker: address(this),
            data: Argument.Stake({isPro: true, voteTokensStaked: 20, fee: 1, sharesOut: 22})
        });
        _arborVote.stakePro(debateId, argumentId, 20);
    }

    function test_tallyTree_emitsDebateFinishedWithTheOutcome() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80); // a supporting argument rated well
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endRating(debateId);

        vm.expectEmit();
        emit IArborVote.DebateFinished({debateId: debateId, approved: true});
        _arborVote.tallyTree(debateId);
    }

    function test_redeemArgumentShares_emitsSharesRedeemed() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80); // reserves 2/8
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, argumentId);
        _endEditing(debateId);

        // fee 1, net 19: pro 2+19=21, con ceil(16/21)=1, shares out 8+19-1=26
        _arborVote.stakeCon(debateId, argumentId, 20);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        // 26 con shares x 21/22 of the market, rounded down: 24 tokens.
        vm.expectEmit();
        emit IArborVote.SharesRedeemed({
            debateId: debateId, argumentId: argumentId, account: address(this), proShares: 0, conShares: 26, payout: 24
        });
        _arborVote.redeemArgumentShares(debateId, argumentId, address(this));
    }

    function test_redeemArgumentShares_emitsNothingWithoutShares() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        vm.recordLogs();
        _arborVote.redeemArgumentShares(debateId, argumentId, makeAddr("uninvolved"));

        assertEq(vm.getRecordedLogs().length, 0);
    }
}
