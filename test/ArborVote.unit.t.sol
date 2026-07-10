// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin-contracts-5.6.1/proxy/utils/Initializable.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {Argument} from "../src/libs/Argument.sol";
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

        // Deploy the implementation behind an ERC1967 UUPS proxy and initialize it in the same transaction.
        ArborVote implementation = new ArborVote();
        _arborVote = ArborVote(
            address(
                new ERC1967Proxy(address(implementation), abi.encodeCall(ArborVote.initialize, (_mockProofOfHumanity)))
            )
        );
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

    // --- initialize ---

    function test_initialize_initializesTheContract() public view {
        assertEq(_arborVote.owner(), address(this));
    }

    function test_initialize_revertsWhenInitializedAgain() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        _arborVote.initialize(_mockProofOfHumanity);
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
        assertEq(_arborVote.getUserTokens(debateId, address(this)), _arborVote.INITIAL_TOKENS());

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

    function test_addArgument_revertsForInitialApprovalsAbove100() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        uint32 initialApproval = 101;
        vm.expectRevert(
            abi.encodeWithSelector(ArborVote.InitialApprovalOutOfBounds.selector, uint32(100), initialApproval)
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

        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 80));
        assertEq(argument.pro, 8);
        assertEq(argument.con, 2);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf100() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 100));
        assertEq(argument.pro, 10);
        assertEq(argument.con, 0);
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

        _arborVote.moveArgument(debateId, argumentC, argumentB);

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

        _arborVote.moveArgument(debateId, childArgumentId, _ROOT_ARGUMENT_ID);

        assertEq(_arborVote.getArgument(debateId, parentArgumentId).childsVote, 0);
        assertEq(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsVote, 20);
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

        assertGt(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsImpact, 0);
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

        assertLt(_arborVote.getArgument(debateId, _ROOT_ARGUMENT_ID).childsImpact, 0);
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
            initialApproval: 100
        });
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT + 1);
        _arborVote.finalizeArgument(debateId, childArgumentId);

        _endRating(debateId);
        _arborVote.tallyTree(debateId);

        // The fully-approved opposing child weakens its parent from below ...
        assertLt(_arborVote.getArgument(debateId, argumentId).childsImpact, 0);
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
}
