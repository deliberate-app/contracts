// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IProofOfHumanity} from "../src/interfaces/IProofOfHumanity.sol";
import {MockProofOfHumanity} from "../test/mocks/MockProofOfHumanity.m.sol";

/// @title DeployLocal
/// @notice A script for local anvil chains: deploys ArborVote with a mock Proof of Humanity that registers
/// every account, and seeds a sample debate so a frontend has data to show.
contract DeployLocal is Script {
    uint48 internal constant _TIME_UNIT = 1 hours;

    function run() public returns (address arborVote) {
        vm.startBroadcast();

        MockProofOfHumanity poh = new MockProofOfHumanity();

        arborVote = address(new ArborVote(IProofOfHumanity(address(poh))));

        // Seed a debate. Only depth-1 arguments can be added here: child arguments require
        // a finalized parent, and finalization needs one time unit to pass.
        ArborVote arbor = ArborVote(arborVote);
        uint256 debateId = arbor.createDebate({contentURI: _toIpfsCid("Fight climate change?"), timeUnit: _TIME_UNIT});
        arbor.join(debateId);

        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Threatens habitability"),
            isSupporting: true,
            initialApproval: 85
        });
        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Cheaper to act now"),
            isSupporting: true,
            initialApproval: 70
        });
        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Transition creates jobs"),
            isSupporting: true,
            initialApproval: 60
        });
        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Slows poor countries"),
            isSupporting: false,
            initialApproval: 65
        });
        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Free-rider problem"),
            isSupporting: false,
            initialApproval: 55
        });
        arbor.addArgument({
            debateId: debateId,
            parentArgumentId: 0,
            contentURI: _toIpfsCid("Innovation will fix it"),
            isSupporting: false,
            initialApproval: 50
        });

        vm.stopBroadcast();
    }

    /// @dev Hashes seed content the way IPFS hashes raw-leaves blocks: the sha-256 multihash digest
    /// of the raw bytes, i.e. the digest inside the content's CIDv1 (raw codec). Pinning the same
    /// bytes with `ipfs add --raw-leaves --cid-version=1` yields a CID wrapping exactly this digest.
    function _toIpfsCid(string memory text) internal pure returns (bytes32 content) {
        content = sha256(bytes(text));
    }
}
