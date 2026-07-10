// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Script} from "forge-std-1.16.1/src/Script.sol";

import {ArborVote} from "../src/ArborVote.sol";

/// @title SeedLocal
/// @notice Deepens the sample debate seeded by `DeployLocal.s.sol` on a local anvil chain.
/// Run `level2` after warping one time unit past the level-1 creation (`cast rpc evm_increaseTime 3601`
/// + `cast rpc evm_mine`), and `level3` after warping once more: child arguments require finalized
/// parents, and finalization unlocks one time unit after creation.
/// @dev Uses anvil's standard, publicly known dev keys. Argument IDs are deterministic
/// (sequential per debate), so parent IDs are hardcoded to the creation order.
contract SeedLocal is Script {
    uint256 internal constant _DEBATE_ID = 0;

    /// @dev anvil default account #1.
    uint256 internal constant _ANVIL_KEY_1 = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    /// @dev anvil default account #2.
    uint256 internal constant _ANVIL_KEY_2 = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
    /// @dev anvil default account #3.
    uint256 internal constant _ANVIL_KEY_3 = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6;

    /// @notice Adds the second level: replies to the six top-level arguments (IDs 1-6 -> new IDs 7-18).
    function level2(address arborVote) public {
        ArborVote arbor = ArborVote(arborVote);

        // Each participant holds 100 vote tokens and an argument costs 10; account #1
        // adds the first ten arguments, account #2 the remaining two.
        vm.startBroadcast(_ANVIL_KEY_1);
        arbor.join(_DEBATE_ID);

        for (uint16 argumentId = 1; argumentId <= 6; argumentId++) {
            arbor.finalizeArgument(_DEBATE_ID, argumentId);
        }

        // Replies to "Threatens habitability" (1)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 1,
            contentURI: _toIpfsCid(
                "Heatwaves, droughts, and rising seas already displace millions of people every year."
            ),
            isSupporting: true,
            initialApproval: 85
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 1,
            contentURI: _toIpfsCid("Feedback loops such as permafrost thaw risk locking in irreversible warming."),
            isSupporting: true,
            initialApproval: 70
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 1,
            contentURI: _toIpfsCid("Human societies have adapted to major environmental shifts throughout history."),
            isSupporting: false,
            initialApproval: 60
        });

        // Replies to "Cheaper to act now" (2)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 2,
            contentURI: _toIpfsCid("Damage estimates for unchecked warming dwarf the costs of mitigation."),
            isSupporting: true,
            initialApproval: 75
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 2,
            contentURI: _toIpfsCid(
                "Cost projections spanning a century are too uncertain to justify specific spending today."
            ),
            isSupporting: false,
            initialApproval: 55
        });

        // Replies to "Transition creates jobs" (3)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 3,
            contentURI: _toIpfsCid("Renewables are now the cheapest source of new electricity in most of the world."),
            isSupporting: true,
            initialApproval: 80
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 3,
            contentURI: _toIpfsCid(
                "Fossil-fuel regions face concentrated job losses that transition programs rarely replace."
            ),
            isSupporting: false,
            initialApproval: 60
        });

        // Replies to "Slows poor countries" (4)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 4,
            contentURI: _toIpfsCid("Cheap fossil energy underpinned every industrialization to date."),
            isSupporting: true,
            initialApproval: 65
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 4,
            contentURI: _toIpfsCid(
                "Distributed renewables can leapfrog fossil grids, as mobile networks leapfrogged landlines."
            ),
            isSupporting: false,
            initialApproval: 70
        });

        // Reply to "Free-rider problem" (5)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 5,
            contentURI: _toIpfsCid(
                "Coordination problems argue for building enforcement mechanisms, not for doing nothing."
            ),
            isSupporting: false,
            initialApproval: 70
        });
        vm.stopBroadcast();

        vm.startBroadcast(_ANVIL_KEY_2);
        arbor.join(_DEBATE_ID);

        // Replies to "Innovation will fix it" (6)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 6,
            contentURI: _toIpfsCid("Solar power costs fell by roughly ninety percent within a decade."),
            isSupporting: true,
            initialApproval: 75
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 6,
            contentURI: _toIpfsCid(
                "That cost fall was itself the product of decades of public subsidies and policy support."
            ),
            isSupporting: false,
            initialApproval: 65
        });
        vm.stopBroadcast();
    }

    /// @notice Adds the third level: replies to selected second-level arguments (IDs 7-18 -> new IDs 19-24).
    function level3(address arborVote) public {
        ArborVote arbor = ArborVote(arborVote);

        vm.startBroadcast(_ANVIL_KEY_3);
        arbor.join(_DEBATE_ID);

        for (uint16 argumentId = 7; argumentId <= 18; argumentId++) {
            arbor.finalizeArgument(_DEBATE_ID, argumentId);
        }

        // Replies to "displace millions of people" (7)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 7,
            contentURI: _toIpfsCid("Small island nations already face permanent submersion of inhabited land."),
            isSupporting: true,
            initialApproval: 75
        });
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 7,
            contentURI: _toIpfsCid(
                "Attribution of migration to climate alone is contested; most moves have mixed causes."
            ),
            isSupporting: false,
            initialApproval: 55
        });

        // Reply to "societies have adapted" (9)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 9,
            contentURI: _toIpfsCid(
                "The projected pace of warming outstrips anything societies have adapted to before."
            ),
            isSupporting: false,
            initialApproval: 70
        });

        // Reply to "projections too uncertain" (11)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 11,
            contentURI: _toIpfsCid(
                "Uncertainty cuts both ways: damages could just as well be far worse than projected."
            ),
            isSupporting: false,
            initialApproval: 70
        });

        // Reply to "renewables can leapfrog" (15)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 15,
            contentURI: _toIpfsCid("Off-grid solar already powers tens of millions of homes across Africa and Asia."),
            isSupporting: true,
            initialApproval: 65
        });

        // Reply to "solar costs fell" (17)
        arbor.addArgument({
            debateId: _DEBATE_ID,
            parentArgumentId: 17,
            contentURI: _toIpfsCid("Cheap panels alone don't decarbonize grids; storage and transmission still lag."),
            isSupporting: false,
            initialApproval: 60
        });
        vm.stopBroadcast();
    }

    /// @dev Hashes seed content the way IPFS hashes raw-leaves blocks; see `DeployLocal.s.sol`.
    function _toIpfsCid(string memory text) internal pure returns (bytes32 content) {
        content = sha256(bytes(text));
    }
}
