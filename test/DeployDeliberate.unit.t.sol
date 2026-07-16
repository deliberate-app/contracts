// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployDeliberate} from "../script/DeployDeliberate.s.sol";
import {Deliberate} from "../src/Deliberate.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract DeployDeliberateTest is Test {
    DeployDeliberate internal _script;

    function setUp() public {
        _script = new DeployDeliberate();
    }

    function test_run_deploysDeliberateAgainstTheGivenRegistry() public {
        MockIdentityRegistry registry = new MockIdentityRegistry();

        address arborVote = _script.run(address(registry));
        assertGt(arborVote.code.length, 0);

        // The given registry is wired into the join gate: an account it denies cannot join.
        uint256 debateId = Deliberate(arborVote)
            .createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: 60,
            editingDuration: 7 * 60,
            ratingDuration: 3 * 60,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
        address denied = makeAddr("denied");
        registry.deny(denied);
        vm.expectRevert(Deliberate.IdentityProofInvalid.selector);
        vm.prank(denied);
        Deliberate(arborVote).join(debateId);
    }

    function test_runWithMockRegistry_deploysThePair() public {
        (address arborVote, address identityRegistry) = _script.runWithMockRegistry();

        assertGt(arborVote.code.length, 0);
        assertGt(identityRegistry.code.length, 0);
        // The mock admits everyone, so any account can join the debates deployed against it.
        assertTrue(MockIdentityRegistry(identityRegistry).isRegistered(makeAddr("anyone")));
    }
}
