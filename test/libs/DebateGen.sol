// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {ArborVote} from "../../src/ArborVote.sol";
import {Argument} from "../../src/libs/Argument.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {Phase} from "../../src/libs/Phase.sol";
import {User} from "../../src/libs/User.sol";

// A test-only DSL for generating example debates against an `ArborVote` deployment.
// solhint-disable private-vars-leading-underscore
library DebateGen {
    // A lightweight handle to a debate under construction: the deployment plus the debate id.
    struct Debate {
        ArborVote arborVote;
        uint256 id;
    }

    // The id of the thesis (root) argument, addressable as the parent of any top-level argument.
    uint16 internal constant ROOT = 0;

    // --- create ---

    function createDebate(Vm vm, ArborVote arborVote, address creator, uint48 lockingDuration)
        internal
        returns (Debate memory debate)
    {
        vm.prank(creator);
        // The thesis is argument 0, so its content is bytes32(0) under the "content is the id" convention.
        // One knob for tests: the classic 7/3 split derives both phases from the locking duration.
        uint256 id = arborVote.createDebate({
            contentURI: bytes32(0),
            lockingDuration: lockingDuration,
            editingDuration: 7 * lockingDuration,
            ratingDuration: 3 * lockingDuration
        });
        debate = Debate({arborVote: arborVote, id: id});
    }

    // --- participants ---

    function join(Vm vm, Debate memory debate, address account) internal {
        if (debate.arborVote.getUserRole(debate.id, account) != User.Role.Participant) {
            vm.prank(account);
            debate.arborVote.join(debate.id);
        }
    }

    // --- arguments (content is the argument id) ---

    function addArgument(
        Vm vm,
        Debate memory debate,
        address author,
        uint16 parentId,
        bool isSupporting,
        uint32 initialApproval,
        uint32 deposit
    ) internal returns (uint16 argumentId) {
        join(vm, debate, author);
        // The next id is the current argument count (ids are dense from 0); use it as the content.
        (, uint16 nextId) = debate.arborVote.debates(debate.id);
        vm.prank(author);
        argumentId = debate.arborVote
            .addArgument({
                debateId: debate.id,
                parentArgumentId: parentId,
                contentURI: bytes32(uint256(nextId)),
                isSupporting: isSupporting,
                initialApproval: initialApproval,
                deposit: deposit
            });
    }

    function addPro(Vm vm, Debate memory debate, address author, uint16 parentId, uint32 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = addArgument({
            vm: vm,
            debate: debate,
            author: author,
            parentId: parentId,
            isSupporting: true,
            initialApproval: initialApproval,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
    }

    function addCon(Vm vm, Debate memory debate, address author, uint16 parentId, uint32 initialApproval)
        internal
        returns (uint16 argumentId)
    {
        argumentId = addArgument({
            vm: vm,
            debate: debate,
            author: author,
            parentId: parentId,
            isSupporting: false,
            initialApproval: initialApproval,
            deposit: Parameters._MIN_DEBATE_DEPOSIT
        });
    }

    // --- staking ---

    function stakePro(Vm vm, Debate memory debate, address staker, uint16 argumentId, uint32 amount) internal {
        join(vm, debate, staker);
        vm.prank(staker);
        debate.arborVote.stakePro(debate.id, argumentId, amount);
    }

    function stakeCon(Vm vm, Debate memory debate, address staker, uint16 argumentId, uint32 amount) internal {
        join(vm, debate, staker);
        vm.prank(staker);
        debate.arborVote.stakeCon(debate.id, argumentId, amount);
    }

    // --- time ---

    function warpWindows(Vm vm, Debate memory debate, uint48 lockingWindows) internal {
        (,,, uint48 lockingDuration) = debate.arborVote.phases(debate.id);
        vm.warp(vm.getBlockTimestamp() + uint256(lockingWindows) * lockingDuration);
    }

    function warpToRating(Vm vm, Debate memory debate) internal {
        (, uint48 editingEndTime,,) = debate.arborVote.phases(debate.id);
        _warpAtLeast(vm, uint256(editingEndTime) + 1);
    }

    function warpToTallying(Vm vm, Debate memory debate) internal {
        (,, uint48 ratingEndTime,) = debate.arborVote.phases(debate.id);
        _warpAtLeast(vm, uint256(ratingEndTime) + 1);
    }

    function warpPastFinalization(Vm vm, Debate memory debate, uint16 argumentId) internal {
        // An argument is final once the clock reaches its finalization time; jump exactly there.
        uint48 finalizationTime = debate.arborVote.getArgument(debate.id, argumentId).finalizationTime;
        _warpAtLeast(vm, uint256(finalizationTime));
    }

    // --- tally ---

    function tally(Vm, Debate memory debate) internal {
        debate.arborVote.tallyTree(debate.id);
    }

    // --- reads (the `Vm` receiver is unused; it keeps the uniform `vm.read(d, ...)` call form) ---

    function argumentOf(Vm, Debate memory debate, uint16 argumentId)
        internal
        view
        returns (Argument.Data memory argument)
    {
        argument = debate.arborVote.getArgument(debate.id, argumentId);
    }

    function phaseOf(Vm, Debate memory debate) internal view returns (Phase.Status status) {
        (status,,,) = debate.arborVote.phases(debate.id);
    }

    function outcome(Vm, Debate memory debate) internal view returns (bool approved) {
        approved = debate.arborVote.outcome(debate.id);
    }

    // Approval is the pro-share price `con / (pro + con)`, in basis points (8000 == 80%); the market-less thesis
    // reads as a neutral 5000.
    function approvalBps(Vm, Debate memory debate, uint16 argumentId) internal view returns (uint256 bps) {
        Argument.Data memory argument = debate.arborVote.getArgument(debate.id, argumentId);
        uint256 total = uint256(argument.pro) + argument.con;
        bps = total == 0 ? 5000 : (uint256(argument.con) * 10000) / total;
    }

    function descendantsImpact(Vm, Debate memory debate, uint16 argumentId) internal view returns (int64 impact) {
        impact = debate.arborVote.getArgument(debate.id, argumentId).descendantsImpact;
    }

    function tokensOf(Vm, Debate memory debate, address account) internal view returns (uint32 tokens) {
        (, tokens) = debate.arborVote.users(debate.id, account);
    }

    // --- internal ---

    function _warpAtLeast(Vm vm, uint256 target) private {
        if (vm.getBlockTimestamp() < target) {
            vm.warp(target);
        }
    }
}
