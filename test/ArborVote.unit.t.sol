// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin-contracts-5.6.1/proxy/utils/Initializable.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {Argument} from "../src/libs/Argument.sol";
import {Phase} from "../src/libs/Phase.sol";
import {User} from "../src/libs/User.sol";
import {MockArbitrator} from "./mocks/MockArbitrator.m.sol";
import {MockERC20} from "./mocks/MockERC20.m.sol";
import {MockProofOfHumanity} from "./mocks/MockProofOfHumanity.m.sol";

contract ArborVoteTest is Test {
    ArborVote internal _arborVote;

    MockProofOfHumanity internal _mockProofOfHumanity;
    MockArbitrator internal _mockArbitrator;
    MockERC20 internal _mockERC20;

    uint48 internal constant _TIME_UNIT = 1 * 60; // 1 minute
    bytes32 internal constant _THESIS_CONTENT = "We should do XYZ";
    bytes32 internal constant _PRO_ARGUMENT_CONTENT = "This is a good idea.";
    uint16 internal constant _ROOT_ARGUMENT_ID = 0;

    function setUp() public {
        _mockProofOfHumanity = new MockProofOfHumanity();
        _mockArbitrator = new MockArbitrator();

        // Deploy the implementation behind an ERC1967 UUPS proxy and initialize it in the same transaction.
        ArborVote implementation = new ArborVote();
        _arborVote = ArborVote(
            address(
                new ERC1967Proxy(address(implementation), abi.encodeCall(ArborVote.initialize, (_mockProofOfHumanity)))
            )
        );

        _mockERC20 = new MockERC20(1000, address(this));
        _mockERC20.approve(address(_arborVote), 1000);
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
        assertEq(uint256(currentPhase), uint256(Phase.Status.Unitialized));

        vm.expectRevert(abi.encodeWithSelector(ArborVote.DebateUninitialized.selector, uninitializedDebateId));
        _arborVote.advancePhase(uninitializedDebateId);
    }

    function test_advancePhase_advancesThePhasesAfterTheTimeHasPassed() public {
        uint256 debateId = _createDebate();

        (Phase.Status currentPhase, uint48 editingEndTime, uint48 votingEndTime,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));

        vm.warp(editingEndTime + 1);
        _arborVote.advancePhase(debateId);
        (currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Voting));

        vm.warp(votingEndTime + 1);
        _arborVote.advancePhase(debateId);
        (currentPhase,,,) = _arborVote.phases(debateId);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Finished));
    }

    // --- createDebate ---

    function test_createDebate_isUninitializedBeforeADebateIsCreated() public view {
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 votingEndTime, uint48 timeUnit) = _arborVote.phases(0);
        assertEq(uint256(currentPhase), uint256(Phase.Status.Unitialized));
        assertEq(editingEndTime, 0);
        assertEq(votingEndTime, 0);
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
        (Phase.Status currentPhase, uint48 editingEndTime, uint48 votingEndTime, uint48 timeUnit) =
            _arborVote.phases(debateId);

        assertEq(uint256(currentPhase), uint256(Phase.Status.Editing));
        assertEq(timeUnit, _TIME_UNIT);
        assertEq(editingEndTime, currentTime + 7 * _TIME_UNIT);
        assertEq(votingEndTime, currentTime + 10 * _TIME_UNIT);
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
        assertEq(_arborVote.getDisputedArgumentIds(debateId).length, 0);
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
        assertEq(_arborVote.getDisputedArgumentIds(debateId).length, 0);
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
        assertEq(_arborVote.getDisputedArgumentIds(debateId).length, 0);
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
        assertEq(argument.pro, 2);
        assertEq(argument.con, 8);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf100() public {
        uint256 debateId = _createDebate();
        _join(debateId);

        Argument.Data memory argument = _arborVote.getArgument(debateId, _addArgument(debateId, true, 100));
        assertEq(argument.pro, 0);
        assertEq(argument.con, 10);
        assertEq(argument.votes, 10);
        assertEq(argument.fees, 0);
    }
}
