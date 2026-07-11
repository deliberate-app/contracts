// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IProofOfHumanity} from "../src/interfaces/IProofOfHumanity.sol";

/// @title DeployArborVote
/// @notice A script deploying the ArborVote contract (not upgradeable, see ADR-0006).
contract DeployArborVote is Script {
    function run(address proofOfHumanity) public returns (address arborVote) {
        vm.startBroadcast();

        arborVote = address(new ArborVote(IProofOfHumanity(proofOfHumanity)));

        vm.stopBroadcast();
    }
}
