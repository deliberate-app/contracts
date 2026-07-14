// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployArborVote} from "../script/DeployArborVote.s.sol";
import {ArborVote} from "../src/ArborVote.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract DeployArborVoteTest is Test {
    DeployArborVote internal _script;

    function setUp() public {
        _script = new DeployArborVote();
    }

    function test_run_deploysArborVoteAgainstTheGivenRegistry() public {
        MockIdentityRegistry registry = new MockIdentityRegistry();

        address arborVote = _script.run(address(registry));
        assertGt(arborVote.code.length, 0);

        // The given registry is wired into the join gate: an account it denies cannot join.
        uint256 debateId = ArborVote(arborVote)
            .createDebate({
            contentURI: "We should do XYZ", lockingDuration: 60, editingDuration: 7 * 60, ratingDuration: 3 * 60
        });
        address denied = makeAddr("denied");
        registry.deny(denied);
        vm.expectRevert(ArborVote.IdentityProofInvalid.selector);
        vm.prank(denied);
        ArborVote(arborVote).join(debateId);
    }

    function test_runWithMockRegistry_deploysThePair() public {
        (address arborVote, address identityRegistry) = _script.runWithMockRegistry();

        assertGt(arborVote.code.length, 0);
        assertGt(identityRegistry.code.length, 0);
        // The mock admits everyone, so any account can join the debates deployed against it.
        assertTrue(MockIdentityRegistry(identityRegistry).isRegistered(makeAddr("anyone")));
    }
}
