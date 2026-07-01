// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ERC1967Proxy} from "@openzeppelin-contracts-5.6.1/proxy/ERC1967/ERC1967Proxy.sol";
import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IProofOfHumanity} from "../src/interfaces/IProofOfHumanity.sol";

/// @title DeployArborVote
/// @notice A script deploying the ArborVote plugin implementation behind an ERC1967 UUPS proxy.
contract DeployArborVote is Script {
    function run(address proofOfHumanity) public returns (address arborVote) {
        vm.startBroadcast();

        ArborVote implementation = new ArborVote();
        arborVote = address(
            new ERC1967Proxy(
                address(implementation), abi.encodeCall(ArborVote.initialize, (IProofOfHumanity(proofOfHumanity)))
            )
        );

        vm.stopBroadcast();
    }
}
