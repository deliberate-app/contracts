// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../../src/Deliberate.sol";
import {Argument} from "../../src/libs/Argument.sol";
import {Parameters} from "../../src/libs/Parameters.sol";
import {Phase} from "../../src/libs/Phase.sol";
import {User} from "../../src/libs/User.sol";

// A test-only DSL for generating example debates against an `Deliberate` deployment.
// solhint-disable private-vars-leading-underscore
library DebateGen {
    // A lightweight handle to a debate under construction: the deployment plus the debate id.
    struct Debate {
        Deliberate deliberate;
        uint256 id;
    }

    // The id of the thesis (root) argument, addressable as the parent of any top-level argument.
    uint16 internal constant ROOT = 0;

    // --- create ---

    // The DSL's standing market fee: the 5% every existing scenario (and the replayed production
    // era) was computed with, so the library's arithmetic stays stable.
    uint32 internal constant FEE_PERCENTAGE = 5;

    function createDebate(Vm vm, Deliberate deliberate, address creator, uint48 lockingDuration)
        internal
        returns (Debate memory debate)
    {
        debate = createDebateWithFee({
            vm: vm,
            deliberate: deliberate,
            creator: creator,
            lockingDuration: lockingDuration,
            feePercentage: FEE_PERCENTAGE
        });
    }

    function createDebateWithFee(
        Vm vm,
        Deliberate deliberate,
        address creator,
        uint48 lockingDuration,
        uint32 feePercentage
    ) internal returns (Debate memory debate) {
        vm.prank(creator);
        // The thesis is argument 0, so its content is bytes32(0) under the "content is the id" convention.
        // One knob for tests: the classic 7/3 split derives both phases from the locking duration.
        uint256 id = deliberate.createDebate({
            contentURI: bytes32(0),
            lockingDuration: lockingDuration,
            editingDuration: 7 * lockingDuration,
            ratingDuration: 3 * lockingDuration,
            feePercentage: feePercentage,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
        debate = Debate({deliberate: deliberate, id: id});
    }

    // --- participants ---

    function join(Vm vm, Debate memory debate, address account) internal {
        if (debate.deliberate.getUserRole(debate.id, account) != User.Role.Participant) {
            vm.prank(account);
            debate.deliberate.join(debate.id);
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
        (, uint16 nextId,,) = debate.deliberate.debates(debate.id);
        vm.prank(author);
        argumentId = debate.deliberate
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
        debate.deliberate.stakePro(debate.id, argumentId, amount);
    }

    function stakeCon(Vm vm, Debate memory debate, address staker, uint16 argumentId, uint32 amount) internal {
        join(vm, debate, staker);
        vm.prank(staker);
        debate.deliberate.stakeCon(debate.id, argumentId, amount);
    }

    // --- time ---

    function warpWindows(Vm vm, Debate memory debate, uint48 lockingWindows) internal {
        (,,, uint48 lockingDuration) = debate.deliberate.phases(debate.id);
        vm.warp(vm.getBlockTimestamp() + uint256(lockingWindows) * lockingDuration);
    }

    function warpToRating(Vm vm, Debate memory debate) internal {
        (, uint48 editingEndTime,,) = debate.deliberate.phases(debate.id);
        _warpAtLeast(vm, uint256(editingEndTime) + 1);
    }

    function warpToTallying(Vm vm, Debate memory debate) internal {
        (,, uint48 ratingEndTime,) = debate.deliberate.phases(debate.id);
        _warpAtLeast(vm, uint256(ratingEndTime) + 1);
    }

    function warpPastFinalization(Vm vm, Debate memory debate, uint16 argumentId) internal {
        // An argument is final once the clock reaches its finalization time; jump exactly there.
        uint48 finalizationTime = debate.deliberate.getArgument(debate.id, argumentId).finalizationTime;
        _warpAtLeast(vm, uint256(finalizationTime));
    }

    // --- tally ---

    function tally(Vm, Debate memory debate) internal {
        debate.deliberate.tallyTree(debate.id);
    }

    // --- settlement (Finished phase; permissionless, so no prank is needed) ---

    function redeem(Vm, Debate memory debate, address account, uint16 argumentId) internal {
        debate.deliberate.redeemArgumentShares(debate.id, argumentId, account);
    }

    function claimFees(Vm, Debate memory debate, uint16 argumentId) internal {
        debate.deliberate.claimFees(debate.id, argumentId);
    }

    // --- reads (the `Vm` receiver is unused; it keeps the uniform `vm.read(d, ...)` call form) ---

    function argumentOf(Vm, Debate memory debate, uint16 argumentId)
        internal
        view
        returns (Argument.Data memory argument)
    {
        argument = debate.deliberate.getArgument(debate.id, argumentId);
    }

    function phaseOf(Vm, Debate memory debate) internal view returns (Phase.Status status) {
        (status,,,) = debate.deliberate.phases(debate.id);
    }

    function outcome(Vm, Debate memory debate) internal view returns (bool approved) {
        approved = debate.deliberate.outcome(debate.id);
    }

    // Approval is the pro-share price `con / (pro + con)`, in basis points (8000 == 80%); the market-less thesis
    // reads as a neutral 5000.
    function approvalBps(Vm, Debate memory debate, uint16 argumentId) internal view returns (uint256 bps) {
        Argument.Data memory argument = debate.deliberate.getArgument(debate.id, argumentId);
        uint256 total = uint256(argument.pro) + argument.con;
        bps = total == 0 ? 5000 : (uint256(argument.con) * 10000) / total;
    }

    function descendantsAggregate(Vm, Debate memory debate, uint16 argumentId) internal view returns (int64 aggregate) {
        aggregate = debate.deliberate.getArgument(debate.id, argumentId).descendantsAggregate;
    }

    function tokensOf(Vm, Debate memory debate, address account) internal view returns (uint32 tokens) {
        (, tokens,) = debate.deliberate.users(debate.id, account);
    }

    function sharesOf(Vm, Debate memory debate, address account, uint16 argumentId)
        internal
        view
        returns (User.Shares memory shares)
    {
        shares = debate.deliberate.getUserShares(debate.id, argumentId, account);
    }

    function totalVotesOf(Vm, Debate memory debate) internal view returns (uint32 totalVotes) {
        (totalVotes,,,) = debate.deliberate.debates(debate.id);
    }

    function feeOf(Vm, Debate memory debate) internal view returns (uint32 feePercentage) {
        (,,, feePercentage) = debate.deliberate.debates(debate.id);
    }

    // --- internal ---

    function _warpAtLeast(Vm vm, uint256 target) private {
        if (vm.getBlockTimestamp() < target) {
            vm.warp(target);
        }
    }
}
