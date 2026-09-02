// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {AllowlistIdentityRegistry} from "../src/adapters/AllowlistIdentityRegistry.sol";
import {Deliberate} from "../src/Deliberate.sol";
import {IDeliberate} from "../src/interfaces/IDeliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {Argument} from "../src/libs/Argument.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {Phase} from "../src/libs/Phase.sol";
import {User} from "../src/libs/User.sol";
import {DebateGen} from "./libs/DebateGen.sol";

contract DeliberateTest is Test {
    using DebateGen for Vm;

    Deliberate internal _deliberate;

    // A curated group, maintained by this contract: the gate the gated-mode tests point their debates at.
    AllowlistIdentityRegistry internal _registry;

    uint48 internal constant _LOCKING_DURATION = 1 minutes;
    bytes32 internal constant _THESIS_CONTENT = "We should do XYZ";
    bytes32 internal constant _PRO_ARGUMENT_CONTENT = "This is a good idea.";
    uint16 internal constant _ROOT_ARGUMENT_ID = 0;

    function setUp() public {
        _registry = new AllowlistIdentityRegistry(address(this));
        _deliberate = new Deliberate();
    }

    // --- helpers ---

    function _createDebate() internal returns (uint256 debateId) {
        debateId = _createDebateWithFee(5);
    }

    function _createDebateWithFee(uint8 feePercentage) internal returns (uint256 debateId) {
        debateId = _createDebate({feePercentage: feePercentage, identityRegistry: IIdentityRegistry(address(0))});
    }

    function _createGatedDebate(IIdentityRegistry identityRegistry) internal returns (uint256 debateId) {
        debateId = _createDebate({feePercentage: 5, identityRegistry: identityRegistry});
    }

    function _createDebate(uint8 feePercentage, IIdentityRegistry identityRegistry)
        internal
        returns (uint256 debateId)
    {
        // The classic 7/3 split: editing spans seven locking windows, rating three.
        debateId = _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: _LOCKING_DURATION,
            editingDuration: 7 * _LOCKING_DURATION,
            ratingDuration: 3 * _LOCKING_DURATION,
            feePercentage: feePercentage,
            identityRegistry: identityRegistry,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function _addArgument(uint256 debateId, bool isSupporting, uint8 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = _addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            isSupporting: isSupporting,
            initialApproval: initialApproval,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
    }

    function _addChild(uint256 debateId, uint16 parentArgumentId, bool isSupporting, uint8 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = _addArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            isSupporting: isSupporting,
            initialApproval: initialApproval,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
    }

    function _addArgument(
        uint256 debateId,
        uint16 parentArgumentId,
        bool isSupporting,
        uint8 initialApproval,
        uint32 deposit
    ) internal returns (uint16 argumentId) {
        argumentId = _deliberate.addArgument({
            debateId: debateId,
            parentArgumentId: parentArgumentId,
            contentURI: _PRO_ARGUMENT_CONTENT,
            isSupporting: isSupporting,
            initialApproval: initialApproval,
            deposit: deposit
        });
    }

    // Stakes as `staker`, joining the debate first if they have not yet.
    function _stake(uint256 debateId, uint16 argumentId, address staker, bool isPro, uint32 amount) internal {
        if (_deliberate.getUserRole(debateId, staker) != User.Role.Participant) {
            vm.prank(staker);
            _deliberate.join(debateId);
        }
        vm.prank(staker);
        if (isPro) {
            _deliberate.stakePro(debateId, argumentId, amount);
        } else {
            _deliberate.stakeCon(debateId, argumentId, amount);
        }
    }

    // A debate in its rating phase holding one final argument seeded at `initialApproval`, created and staked by
    // this contract: where every staking and settlement scenario starts.
    function _debateInRating(uint8 initialApproval) internal returns (uint256 debateId, uint16 argumentId) {
        debateId = _createDebate();
        _deliberate.join(debateId);
        argumentId = _addArgument(debateId, true, initialApproval);
        _endEditing(debateId);
    }

    function _setMembership(address account, bool member) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        _registry.setMembership(accounts, member);
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

    function _debate(uint256 debateId) internal view returns (DebateGen.Debate memory debate) {
        debate = DebateGen.Debate({deliberate: _deliberate, id: debateId});
    }

    function _fillDebateToTheArgumentCap(uint256 debateId) internal {
        vm.fan(_debate(debateId), _ROOT_ARGUMENT_ID, Parameters.MAX_ARGUMENTS - 1);
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
        (,,, uint8 feePercentage,) = _deliberate.debates(debateId);
        assertEq(feePercentage, 5);
    }

    function test_createDebate_acceptsAZeroAndTheMaximumFee() public {
        uint256 freeDebateId = _createDebateWithFee(0);
        (,,, uint8 freeFee,) = _deliberate.debates(freeDebateId);
        assertEq(freeFee, 0);

        uint256 maxDebateId = _createDebateWithFee(99);
        (,,, uint8 maxFee,) = _deliberate.debates(maxDebateId);
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
            identityRegistry: IIdentityRegistry(address(0)),
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
            identityRegistry: IIdentityRegistry(address(0)),
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
            identityRegistry: IIdentityRegistry(address(0)),
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
            identityRegistry: IIdentityRegistry(address(0)),
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

    function test_createDebate_recordsTheGateItWasGiven() public {
        uint256 openDebateId = _createDebate();
        uint256 gatedDebateId = _createGatedDebate(_registry);

        (,,,, IIdentityRegistry openGate) = _deliberate.debates(openDebateId);
        (,,,, IIdentityRegistry namedGate) = _deliberate.debates(gatedDebateId);

        assertEq(address(openGate), address(0));
        assertEq(address(namedGate), address(_registry));
    }

    // --- join ---

    function test_join_joinsADebate() public {
        uint256 debateId = _createDebate();

        assertEq(uint256(_deliberate.getUserRole(debateId, address(this))), uint256(User.Role.Unassigned));
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 0);

        User.Shares memory shares = _deliberate.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);

        _deliberate.join(debateId);

        assertEq(uint256(_deliberate.getUserRole(debateId, address(this))), uint256(User.Role.Participant));
        assertEq(_deliberate.getUserTokens(debateId, address(this)), Parameters.INITIAL_TOKENS);

        shares = _deliberate.getUserShares(debateId, _ROOT_ARGUMENT_ID, address(this));
        assertEq(shares.pro, 0);
        assertEq(shares.con, 0);
    }

    function test_join_admitsAnyoneWhenTheDebateNamesNoRegistry() public {
        // The open mode, and the reason it is the zero address rather than a registry that answers yes to
        // everything: there is nothing to deploy, and nothing that could later answer differently.
        uint256 debateId = _createDebate();

        vm.prank(makeAddr("a stranger"));
        _deliberate.join(debateId);

        assertEq(uint8(_deliberate.getUserRole(debateId, makeAddr("a stranger"))), uint8(User.Role.Participant));
    }

    function test_join_readsTheRegistryOnlyAtJoinTime() public {
        // Membership decides admission and nothing after it: a debate keeps the participant it admitted when the
        // group later drops them, and it is the next join that the loss bars. That is what lets one curated group
        // serve every debate that names it, each reading it once.
        uint256 firstDebateId = _createGatedDebate(_registry);
        uint256 secondDebateId = _createGatedDebate(_registry);
        address member = makeAddr("member");
        _setMembership(member, true);

        vm.prank(member);
        _deliberate.join(firstDebateId);

        _setMembership(member, false);

        vm.prank(member);
        uint16 argumentId = _addArgument(firstDebateId, true, 50);
        assertEq(_deliberate.getArgument(firstDebateId, argumentId).creator, member);

        vm.expectRevert(Deliberate.IdentityProofInvalid.selector);
        vm.prank(member);
        _deliberate.join(secondDebateId);
    }

    function test_join_succeedsDuringTheRatingPhase() public {
        uint256 debateId = _createDebate();
        _endEditing(debateId);

        _deliberate.join(debateId);

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
        _deliberate.join(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.RoleInvalid.selector, User.Role.Unassigned, User.Role.Participant)
        );
        _deliberate.join(debateId);
    }

    // --- addArgument ---

    function test_addArgument_incrementsTheArgumentId() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        assertEq(_addArgument(debateId, true, 50), 1);
        assertEq(_addArgument(debateId, true, 50), 2);
    }

    function test_addArgument_addsAProArgument() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 proArgumentId = _addArgument(debateId, true, 50);

        Argument.Data memory proArgument = _deliberate.getArgument(debateId, proArgumentId);
        assertEq(proArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(proArgument.pro, 500);
        assertEq(proArgument.con, 500);
        assertEq(proArgument.votes, 1000);
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
        _deliberate.join(debateId);

        uint16 conArgumentId = _addArgument(debateId, false, 50);

        Argument.Data memory conArgument = _deliberate.getArgument(debateId, conArgumentId);
        assertEq(conArgument.contentURI, _PRO_ARGUMENT_CONTENT);

        assertEq(conArgument.pro, 500);
        assertEq(conArgument.con, 500);
        assertEq(conArgument.votes, 1000);
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
        _deliberate.join(debateId);

        uint8 initialApproval = 49;
        vm.expectRevert(abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, 50, initialApproval));
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_revertsForInitialApprovalsAbove99() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // 100 would empty the pro reserve and freeze the market.
        uint8 initialApproval = 100;
        vm.expectRevert(abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, 99, initialApproval));
        _addArgument(debateId, true, initialApproval);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf50() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 50));
        assertEq(argument.pro, 500);
        assertEq(argument.con, 500);
        assertEq(argument.votes, 1000);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf80() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // Approval is the pro-share price: 80% approval means a scarce pro reserve.
        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 80));
        assertEq(argument.pro, 200);
        assertEq(argument.con, 800);
        assertEq(argument.votes, 1000);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_initializesTheArgumentWithAnInitialApprovalOf95() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // Seeding is exact at the scale the deposit carries: 5% of 1000 to pro, 95% to con - where a
        // hundred-unit budget could only reach 90%, ten points off what the creator asked for.
        Argument.Data memory argument = _deliberate.getArgument(debateId, _addArgument(debateId, true, 95));
        assertEq(argument.pro, 50);
        assertEq(argument.con, 950);
        assertEq(argument.votes, 1000);
        assertEq(argument.fees, 0);
    }

    function test_addArgument_addsTheDepositToTheParentWeightAndDebateTotal() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        _addArgument(debateId, true, 50);
        _addArgument(debateId, false, 50);

        // Stake weights are tally-time state; only the debate total is maintained on the way in.
        assertEq(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).subtreeVotes, 0);

        (uint32 totalVotes,,,,) = _deliberate.debates(debateId);
        assertEq(totalVotes, 2000);
    }

    function test_addArgument_stakesTheChosenDeposit() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // The creator stakes 4000 (above the minimum) at 50% approval: the deposit splits evenly
        // into the reserves, seeds the votes, and counts in full toward the parent and debate totals.
        uint16 argumentId = _addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            isSupporting: true,
            initialApproval: 50,
            deposit: 4000
        });
        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 2000);
        assertEq(argument.con, 2000);
        assertEq(argument.votes, 4000);

        (uint32 totalVotes,,,,) = _deliberate.debates(debateId);
        assertEq(totalVotes, 4000);
        assertEq(_deliberate.getUserTokens(debateId, address(this)), Parameters.INITIAL_TOKENS - 4000);
    }

    function test_addArgument_revertsForADepositBelowTheMinimum() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint32 deposit = Parameters._MIN_DEBATE_DEPOSIT - 1;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.DepositBelowMinimum.selector, Parameters._MIN_DEBATE_DEPOSIT, deposit)
        );
        _addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            isSupporting: true,
            initialApproval: 50,
            deposit: deposit
        });
    }

    function test_addArgument_revertsWhenTheDepositExceedsTheBalance() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint32 deposit = Parameters.INITIAL_TOKENS + 100;
        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.InsufficientVoteTokens.selector, deposit, Parameters.INITIAL_TOKENS)
        );
        _addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            isSupporting: true,
            initialApproval: 50,
            deposit: deposit
        });
    }

    function test_addArgument_revertsOutsideTheEditingPhase() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        _endEditing(debateId);

        vm.expectRevert(
            abi.encodeWithSelector(Deliberate.PhaseInvalid.selector, Phase.Status.Editing, Phase.Status.Rating)
        );
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_revertsWhenTheArgumentLimitIsReached() public {
        uint256 debateId = _createDebate();
        _fillDebateToTheArgumentCap(debateId);
        _deliberate.join(debateId);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentLimitReached.selector, Parameters.MAX_ARGUMENTS));
        _addArgument(debateId, true, 50);
    }

    function test_addArgument_keepsTheLeavesConsistentAcrossSiblingAdds() public {
        // Regression: removing the parent from the leaf list searched an unsorted array by bisection and,
        // on a miss, silently removed the last element - adding a second child to the same parent
        // dropped an unrelated leaf (and with it the subtree the tally would start from).
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        uint16 argumentB = _addArgument(debateId, false, 50);
        uint16 argumentC = _addChild(debateId, argumentA, true, 50);
        uint16 argumentD = _addChild(debateId, argumentA, false, 50);

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
        _deliberate.join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        uint16 argumentB = _addArgument(debateId, false, 50);
        skip(_LOCKING_DURATION + 1);

        uint16 argumentC = _addChild(debateId, argumentA, true, 50);

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
        _deliberate.join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        uint16 childArgumentId = _addChild(debateId, parentArgumentId, true, 50);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).parentArgumentId, parentArgumentId);

        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: _ROOT_ARGUMENT_ID, initialApproval: 50
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).parentArgumentId, _ROOT_ARGUMENT_ID);
    }

    function test_moveArgument_reseedsTheMarketAtTheNewApproval() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        // A draft seeded at 50% approval: reserves split the deposit evenly.
        uint16 childArgumentId = _addArgument(debateId, true, 50);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 500);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 500);

        // Moving it re-seeds the market at 80%: con takes 80% of the (unchanged) deposit.
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 80
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 200);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 800);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).votes, 1000); // the deposit is unchanged
    }

    function test_moveArgument_reseedsFromTheArgumentDeposit() public {
        // A non-default deposit must re-seed from the argument's own votes, not a fixed constant.
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        // A draft seeded with a 4000-token deposit at 50%: reserves 2000/2000.
        uint16 childArgumentId = _addArgument({
            debateId: debateId,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            isSupporting: true,
            initialApproval: 50,
            deposit: 4000
        });

        // Moving it re-seeds at 80% from the 4000-token deposit: con takes 80% (3200), pro the rest (800).
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 80
        });

        assertEq(_deliberate.getArgument(debateId, childArgumentId).pro, 800);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).con, 3200);
        assertEq(_deliberate.getArgument(debateId, childArgumentId).votes, 4000);
    }

    function test_moveArgument_revertsForAnApprovalOutOfBounds() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 parentArgumentId = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        uint16 childArgumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.InitialApprovalOutOfBounds.selector, 99, 100));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: childArgumentId, newParentArgumentId: parentArgumentId, initialApproval: 100
        });
    }

    function test_moveArgument_revertsForANonFinalNewParent() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentA = _addArgument(debateId, true, 50);
        uint16 argumentB = _addArgument(debateId, false, 50); // a draft, so not a valid parent

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentB));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentA, newParentArgumentId: argumentB, initialApproval: 50
        });
    }

    function test_moveArgument_revertsWhenMovedUnderItself() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        // The argument being moved is necessarily a draft, never final - it cannot be its own final parent.
        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentId));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: argumentId, initialApproval: 50
        });
    }

    function test_moveArgument_revertsForANonexistentNewParent() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, uint16(42)));
        _deliberate.moveArgument({
            debateId: debateId, argumentId: argumentId, newParentArgumentId: 42, initialApproval: 50
        });
    }

    // --- alterArgument ---

    function test_alterArgument_revertsForANonCreator() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        address intruder = makeAddr("intruder");
        vm.expectRevert(abi.encodeWithSelector(Deliberate.AddressInvalid.selector, address(this), intruder));
        vm.prank(intruder);
        _deliberate.alterArgument(debateId, argumentId, "A hijacked idea.");
    }

    function test_alterArgument_revertsOnceTheArgumentIsFinal() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);

        // The draft locks in exactly when its editing window elapses.
        skip(_LOCKING_DURATION);
        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotDraft.selector, argumentId));
        _deliberate.alterArgument(debateId, argumentId, "Too late.");
    }

    function test_alterArgument_revertsWhenTheNewWindowWouldOutliveEditing() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

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
        (uint256 debateId, uint16 argumentId) = _debateInRating(50);

        _deliberate.stakePro(debateId, argumentId, 2000);

        // 100 initial - 10 deposit - 20 staked
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 7000);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        User.Shares memory shares = _deliberate.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.pro, 2295);
        assertEq(shares.con, 0);

        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 105);
        assertEq(argument.con, 2400); // approval con/(pro+con) rose from 50% to 2400/2505 = 95.8%
        assertEq(argument.votes, 2900); // 1000 deposit + 2000 staked - 100 fee
        assertEq(argument.fees, 100); // 5% of 2000
    }

    function test_stakeCon_buysConSharesAndLowersTheApproval() public {
        (uint256 debateId, uint16 argumentId) = _debateInRating(50);

        _deliberate.stakeCon(debateId, argumentId, 2000);

        // fee 1, net 19: pro 5+19=24, con ceil(25/24)=2, shares out 22
        User.Shares memory shares = _deliberate.getUserShares(debateId, argumentId, address(this));
        assertEq(shares.con, 2295);
        assertEq(shares.pro, 0);

        Argument.Data memory argument = _deliberate.getArgument(debateId, argumentId);
        assertEq(argument.pro, 2400);
        assertEq(argument.con, 105); // approval fell from 50% to 105/12105 - rated as bad
    }

    /// @dev Pins the market's defining behavior: buying a side always moves the approval - the
    /// price of belief, con/(pro+con) - toward that side, never away from it. Compared through
    /// cross-multiplication to avoid integer division.
    function testFuzz_stake_movesTheApprovalTowardTheBoughtSide(uint8 initialApproval, bool isPro, uint32 amount)
        public
    {
        initialApproval = uint8(bound(initialApproval, 50, 99));
        amount = uint32(bound(amount, 1, Parameters.INITIAL_TOKENS));

        (uint256 debateId, uint16 argumentId) = _debateInRating(initialApproval);

        Argument.Data memory before = _deliberate.getArgument(debateId, argumentId);

        _stake({debateId: debateId, argumentId: argumentId, staker: makeAddr("staker"), isPro: isPro, amount: amount});

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

    /// @dev Redemption can never pay out more than the market's collateral, whatever is traded,
    /// whenever it is traded, and however the sub-debate corrects the settlement away from the
    /// market's own price: any rating in [-MAX, MAX] pays at most one full side's shares, covered
    /// by the deposit and net stakes.
    function testFuzz_redeem_staysWithinTheMarketCollateral(
        uint8 initialApproval,
        bool firstIsPro,
        uint32 firstAmount,
        bool secondIsPro,
        uint32 secondAmount,
        uint48 secondDelay,
        bool childIsSupporting,
        uint8 childApproval
    ) public {
        initialApproval = uint8(bound(initialApproval, 50, 99));
        firstAmount = uint32(bound(firstAmount, 1, Parameters.INITIAL_TOKENS));
        secondAmount = uint32(bound(secondAmount, 1, Parameters.INITIAL_TOKENS));
        // The rating window is three locking durations; the second stake lands anywhere inside it.
        secondDelay = uint48(bound(secondDelay, 0, 3 * _LOCKING_DURATION - 1));
        childApproval = uint8(bound(childApproval, 50, 99));

        uint256 debateId = _createDebate();
        _deliberate.join(debateId);
        uint16 argumentId = _addArgument(debateId, true, initialApproval);
        skip(_LOCKING_DURATION + 1);

        // A sub-debate beneath the argument corrects its settlement away from its own price.
        _addChild(debateId, argumentId, childIsSupporting, childApproval);
        _endEditing(debateId);

        address firstStaker = makeAddr("firstStaker");
        address secondStaker = makeAddr("secondStaker");

        _stake({
            debateId: debateId, argumentId: argumentId, staker: firstStaker, isPro: firstIsPro, amount: firstAmount
        });

        skip(secondDelay);
        _stake({
            debateId: debateId, argumentId: argumentId, staker: secondStaker, isPro: secondIsPro, amount: secondAmount
        });

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
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endEditing(debateId);

        uint32 balance = _deliberate.getUserTokens(debateId, address(this));
        vm.expectRevert(abi.encodeWithSelector(Deliberate.InsufficientVoteTokens.selector, balance + 1, balance));
        _deliberate.stakePro(debateId, argumentId, balance + 1);
    }

    function test_stakePro_revertsForTheThesis() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);
        _endEditing(debateId);

        // The thesis is Final from creation but has no market of its own.
        vm.expectRevert(Deliberate.ThesisHasNoMarket.selector);
        _deliberate.stakePro(debateId, _ROOT_ARGUMENT_ID, 1000);
    }

    function test_stakePro_revertsForANonFinalArgument() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // Add an argument late in the editing window so it is still a draft once rating begins: its
        // finalization time (one locking window out) lands after the editing deadline.
        (, uint48 editingEndTime,,) = _deliberate.phases(debateId);
        vm.warp(editingEndTime - 1);
        uint16 argumentId = _addArgument(debateId, true, 50);
        _endEditing(debateId); // now in rating, but the argument's window has not closed yet

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, argumentId));
        _deliberate.stakePro(debateId, argumentId, 1000);
    }

    function test_stakeCon_revertsForANonexistentArgument() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);
        _endEditing(debateId);

        vm.expectRevert(abi.encodeWithSelector(Deliberate.ArgumentNotFinal.selector, uint16(42)));
        _deliberate.stakeCon(debateId, 42, 1000);
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
        _deliberate.join(debateId);

        _addArgument(debateId, true, 80);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertGt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsAggregate, 0);
        assertTrue(_deliberate.outcome(debateId));
    }

    function test_tallyTree_talliesAnOpposingArgumentIntoANegativeOutcome() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        _addArgument(debateId, false, 80);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertLt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsAggregate, 0);
        assertFalse(_deliberate.outcome(debateId));
    }

    function test_tallyTree_settlesAMaximallyDeepChain() public {
        // The cap bounds the tree's size, not its shape, and the deepest reachable shape is a single chain: depth
        // costs only one locking window per level, which a creator sets. The gas benchmarks measure both extremes;
        // this pins that the deepest one settles to the root at all, which no other test exercises beyond a
        // couple of levels.
        uint256 debateId = _deliberate.createDebate({
            contentURI: _THESIS_CONTENT,
            lockingDuration: 1,
            editingDuration: 4 * uint48(Parameters.MAX_ARGUMENTS),
            ratingDuration: 100,
            feePercentage: 5,
            identityRegistry: IIdentityRegistry(address(0)),
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });

        vm.chain(_debate(debateId), _ROOT_ARGUMENT_ID, Parameters.MAX_ARGUMENTS - 1);
        (, uint16 argumentsCount,,,) = _deliberate.debates(debateId);
        assertEq(argumentsCount, Parameters.MAX_ARGUMENTS, "the chain must reach the cap to bound the deepest tally");

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // Settled to the root: every level folded into its parent, and the debate reached its terminal phase.
        (Phase.Status currentPhase,,,) = _deliberate.phases(debateId);
        assertEq(uint8(currentPhase), uint8(Phase.Status.Finished));
        assertEq(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).untalliedChilds, 0);
    }

    function test_tallyTree_finalizesArgumentsByTime() public {
        // No explicit finalize step: an argument left untouched becomes final once its editing window elapses
        // (by the Tallying phase, always), so it is tallied automatically.
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        _addArgument(debateId, true, 95); // supporting, seeded high; never touched again
        _endRating(debateId);

        _deliberate.tallyTree(debateId);

        assertGt(_deliberate.getArgument(debateId, _ROOT_ARGUMENT_ID).descendantsAggregate, 0);
        assertTrue(_deliberate.outcome(debateId));
    }

    function test_tallyTree_talliesRecursivelyUpTheTree() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 80);
        skip(_LOCKING_DURATION + 1);
        _addChild(debateId, argumentId, false, 95);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // The fully-approved opposing child weakens its parent from below ...
        assertLt(_deliberate.getArgument(debateId, argumentId).descendantsAggregate, 0);
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
        (uint256 debateId, uint16 argumentId) = _debateInRating(50);

        address earlyStaker = makeAddr("earlyStaker");
        address lateStaker = makeAddr("lateStaker");

        // The early staker buys pro cheap at 50% approval: 13 shares for 10 tokens (-> 88.2%).
        _stake({debateId: debateId, argumentId: argumentId, staker: earlyStaker, isPro: true, amount: 1000});

        // The crowd confirms the rating later, at a higher price: 20 shares for 20 tokens (-> 97.1%).
        _stake({debateId: debateId, argumentId: argumentId, staker: lateStaker, isPro: true, amount: 2000});

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        _deliberate.redeemArgumentShares(debateId, argumentId, earlyStaker);
        _deliberate.redeemArgumentShares(debateId, argumentId, lateStaker);

        // Early: 13 shares settling at the tallied rating (~96.9% on the price scale) = 12 tokens
        // back on 10 staked - correcting the rating early pays.
        assertEq(_deliberate.getUserTokens(debateId, earlyStaker), 10245);
        // Late: 20 shares at the same settlement = 19 tokens back on 20 staked - fee and slippage
        // eat the late trade.
        assertEq(_deliberate.getUserTokens(debateId, lateStaker), 9948);
        // Solvency: 12 + 19 paid out of the market's 39 collateral tokens.
    }

    // --- redeemArgumentSharesBatch ---

    function test_redeemArgumentSharesBatch_redeemsAcrossArguments() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argument1 = _addArgument(debateId, true, 50); // reserves 5/5
        uint16 argument2 = _addArgument(debateId, true, 50); // reserves 5/5
        _endEditing(debateId);

        // One staker takes a con position in both arguments (22 con shares each).
        address staker = makeAddr("staker");
        _stake({debateId: debateId, argumentId: argument1, staker: staker, isPro: false, amount: 2000});
        _stake({debateId: debateId, argumentId: argument2, staker: staker, isPro: false, amount: 2000});
        assertEq(_deliberate.getUserTokens(debateId, staker), 6000); // 100 - 20 - 20

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        uint16[] memory argumentIds = new uint16[](2);
        argumentIds[0] = argument1;
        argumentIds[1] = argument2;
        _deliberate.redeemArgumentSharesBatch(debateId, argumentIds, staker);

        // Both positions redeemed in one call: 20 tokens back per argument.
        assertEq(_deliberate.getUserShares(debateId, argument1, staker).con, 0);
        assertEq(_deliberate.getUserShares(debateId, argument2, staker).con, 0);
        assertEq(_deliberate.getUserTokens(debateId, staker), 10384);
    }

    function test_redeemArgumentSharesBatch_skipsArgumentsWithoutShares() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argument1 = _addArgument(debateId, true, 50);
        uint16 argument2 = _addArgument(debateId, true, 50);
        _endEditing(debateId);

        // The staker only holds shares in argument1.
        address staker = makeAddr("staker");
        _stake({debateId: debateId, argumentId: argument1, staker: staker, isPro: false, amount: 2000});

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // The batch includes argument2, which the staker never staked on: it is skipped, not reverted.
        uint16[] memory argumentIds = new uint16[](2);
        argumentIds[0] = argument1;
        argumentIds[1] = argument2;
        _deliberate.redeemArgumentSharesBatch(debateId, argumentIds, staker);

        assertEq(_deliberate.getUserShares(debateId, argument1, staker).con, 0);
        assertEq(_deliberate.getUserTokens(debateId, staker), 10192); // argument2 a no-op
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
        (uint256 debateId, uint16 argumentId) = _debateInRating(50);

        // A second participant stakes 20; the 5% fee (1 token) accrues to the argument.
        address staker = makeAddr("staker");
        _stake({debateId: debateId, argumentId: argumentId, staker: staker, isPro: true, amount: 2000});

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        assertEq(_deliberate.getUserTokens(debateId, address(this)), 9000); // 100 - 10 deposit

        _deliberate.claimFees(debateId, argumentId);

        assertEq(_deliberate.getUserTokens(debateId, address(this)), 9100); // + 1 fee
        assertEq(_deliberate.getArgument(debateId, argumentId).fees, 0);

        // A second claim is a no-op.
        _deliberate.claimFees(debateId, argumentId);
        assertEq(_deliberate.getUserTokens(debateId, address(this)), 9100);
    }

    function test_claimFees_revertsWhileTheDebateIsNotFinished() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

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
            feePercentage: 5,
            identityRegistry: IIdentityRegistry(address(0))
        });
        _createDebate();
    }

    function test_join_emitsJoined() public {
        uint256 debateId = _createDebate();

        vm.expectEmit();
        emit IDeliberate.Joined({debateId: debateId, account: address(this), tokens: Parameters.INITIAL_TOKENS});
        _deliberate.join(debateId);
    }

    function test_addArgument_emitsArgumentAddedWithTheSeededMarket() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        // An 80% initial approval seeds a scarce pro reserve: 2 pro / 8 con.
        vm.expectEmit();
        emit IDeliberate.ArgumentAdded({
            debateId: debateId,
            argumentId: 1,
            parentArgumentId: _ROOT_ARGUMENT_ID,
            creator: address(this),
            isSupporting: true,
            contentURI: _PRO_ARGUMENT_CONTENT,
            pro: 200,
            con: 800,
            finalizationTime: uint48(vm.getBlockTimestamp()) + _LOCKING_DURATION
        });
        _addArgument(debateId, true, 80);
    }

    function test_moveArgument_emitsArgumentMoved() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 newParentArgumentId = _addArgument(debateId, true, 50);
        skip(_LOCKING_DURATION + 1);
        uint16 movedArgumentId = _addArgument(debateId, false, 50);

        vm.expectEmit();
        emit IDeliberate.ArgumentMoved({
            debateId: debateId,
            argumentId: movedArgumentId,
            newParentArgumentId: newParentArgumentId,
            oldParentArgumentId: _ROOT_ARGUMENT_ID,
            pro: 200,
            con: 800
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
        _deliberate.join(debateId);

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
        (uint256 debateId, uint16 argumentId) = _debateInRating(50);

        // fee 1, net 19: con 5+19=24, pro ceil(25/24)=2, shares out 5+19-2=22
        vm.expectEmit();
        emit IDeliberate.Staked({
            debateId: debateId,
            argumentId: argumentId,
            staker: address(this),
            data: Argument.Stake({isPro: true, voteTokensStaked: 2000, fee: 100, sharesOut: 2295})
        });
        _deliberate.stakePro(debateId, argumentId, 2000);
    }

    function test_tallyTree_emitsDebateFinishedWithTheOutcome() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        _addArgument(debateId, true, 80); // a supporting argument rated well, finalized by time at the tally
        _endRating(debateId);

        vm.expectEmit();
        emit IDeliberate.DebateFinished({debateId: debateId, approved: true});
        _deliberate.tallyTree(debateId);
    }

    function test_redeemArgumentShares_emitsSharesRedeemed() public {
        (uint256 debateId, uint16 argumentId) = _debateInRating(80);

        // fee 1, net 19: pro 2+19=21, con ceil(16/21)=1, shares out 8+19-1=26
        _deliberate.stakeCon(debateId, argumentId, 2000);

        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        // 26 con shares x 21/22 of the market, rounded down: 24 tokens.
        vm.expectEmit();
        emit IDeliberate.SharesRedeemed({
            debateId: debateId,
            argumentId: argumentId,
            account: address(this),
            proShares: 0,
            conShares: 2623,
            payout: 2519
        });
        _deliberate.redeemArgumentShares(debateId, argumentId, address(this));
    }

    function test_redeemArgumentShares_emitsNothingWithoutShares() public {
        uint256 debateId = _createDebate();
        _deliberate.join(debateId);

        uint16 argumentId = _addArgument(debateId, true, 50);
        _endRating(debateId);
        _deliberate.tallyTree(debateId);

        vm.recordLogs();
        _deliberate.redeemArgumentShares(debateId, argumentId, makeAddr("uninvolved"));

        assertEq(vm.getRecordedLogs().length, 0);
    }
}
