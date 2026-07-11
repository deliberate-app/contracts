// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IProofOfHumanity} from "../src/interfaces/IProofOfHumanity.sol";
import {MockProofOfHumanity} from "../test/mocks/MockProofOfHumanity.m.sol";

/// @title DeployArborVote
/// @notice A script deploying the ArborVote contract (not upgradeable, see ADR-0006).
contract DeployArborVote is Script {
    /// @notice Deploys ArborVote against an existing Proof of Humanity registry.
    function run(address proofOfHumanity) public returns (address arborVote) {
        vm.startBroadcast();

        arborVote = address(new ArborVote(IProofOfHumanity(proofOfHumanity)));

        vm.stopBroadcast();
    }

    /// @notice Deploys a MockProofOfHumanity (everyone counts as registered) alongside
    /// ArborVote - for test networks without a real Proof of Humanity registry.
    function runWithMockPoH() public returns (address arborVote, address proofOfHumanity) {
        vm.startBroadcast();

        proofOfHumanity = address(new MockProofOfHumanity());
        arborVote = address(new ArborVote(IProofOfHumanity(proofOfHumanity)));

        vm.stopBroadcast();
    }
}
