// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

// Exposes the internal tally/tree plumbing so its defensive guards can be exercised: through the
// public surface their invariants hold by construction, leaving the guards otherwise unreachable.
contract ArborVoteHarness is ArborVote {
    constructor(IIdentityRegistry identityRegistry) ArborVote(identityRegistry) {}

    function exposedTallyNode(uint256 debateId, uint16 argumentId) external {
        _tallyNode(debateId, argumentId);
    }

    function exposedUpdateParentAfterChildRemoval(uint256 debateId, uint16 parentArgumentId) external {
        _updateParentAfterChildRemoval(debateId, parentArgumentId);
    }
}

contract ArborVoteHarnessTest is Test {
    uint48 internal constant _TIME_UNIT = 1 * 60; // 1 minute

    ArborVoteHarness internal _arborVote;

    function setUp() public {
        _arborVote = new ArborVoteHarness(new MockIdentityRegistry());
    }

    function _debateWithADraft() internal returns (uint256 debateId, uint16 argumentId) {
        debateId = _arborVote.createDebate("We should do XYZ", _TIME_UNIT);
        _arborVote.join(debateId);
        argumentId = _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: "This is a good idea.",
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
    }

    // tallyTree tallies leaves first and only recurses into a parent once its counter reaches zero,
    // so this guard never fires through the public surface; it protects the tally against leaf
    // bookkeeping breaking.
    function test_tallyNode_revertsWhileChildrenAreUntallied() public {
        (uint256 debateId, uint16 parentId) = _debateWithADraft();

        // Give the argument a child of its own, once it has locked in and can be replied to.
        vm.warp(vm.getBlockTimestamp() + _TIME_UNIT);
        _arborVote.addArgument({
            debateId: debateId,
            parentArgumentId: parentId,
            contentURI: "A supporting detail.",
            isSupporting: true,
            initialApproval: 50,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });

        // Jump straight to tallying the interior node, skipping its child.
        (,, uint48 ratingEndTime,) = _arborVote.phases(debateId);
        vm.warp(ratingEndTime + 1);
        vm.expectRevert(abi.encodeWithSelector(ArborVote.ChildsUntallied.selector, uint16(1)));
        _arborVote.exposedTallyNode(debateId, parentId);
    }

    // Children only attach beneath final parents and finality is time-monotone, so a moved draft's
    // old parent is always final; the guard protects the leaf bookkeeping against that invariant
    // breaking.
    function test_updateParentAfterChildRemoval_revertsForANonFinalParent() public {
        (uint256 debateId, uint16 argumentId) = _debateWithADraft();

        vm.expectRevert(abi.encodeWithSelector(ArborVote.ArgumentNotFinal.selector, argumentId));
        _arborVote.exposedUpdateParentAfterChildRemoval(debateId, argumentId);
    }
}
