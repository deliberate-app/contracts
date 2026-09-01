// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {DeployDeliberate} from "../script/DeployDeliberate.s.sol";
import {Deliberate} from "../src/Deliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {MockIdentityRegistry} from "./mocks/MockIdentityRegistry.m.sol";

contract DeployDeliberateTest is Test {
    DeployDeliberate internal _script;

    function setUp() public {
        _script = new DeployDeliberate();
    }

    function _createDebate(Deliberate deliberate, IIdentityRegistry identityRegistry)
        internal
        returns (uint256 debateId)
    {
        debateId = deliberate.createDebate({
            contentURI: "We should do XYZ",
            lockingDuration: 60,
            editingDuration: 7 * 60,
            ratingDuration: 3 * 60,
            feePercentage: 5,
            identityRegistry: identityRegistry,
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
    }

    function test_run_deploysDeliberate() public {
        address deliberate = _script.run();

        assertGt(deliberate.code.length, 0);
    }

    function test_run_deploysAContractWhoseDebatesChooseTheirOwnGate() public {
        // One deployment serves every mode, which is why the script takes no arguments: the gate is a
        // property of each debate, not of the contract they all live in.
        Deliberate deliberate = Deliberate(_script.run());
        MockIdentityRegistry registry = new MockIdentityRegistry();

        uint256 openDebateId = _createDebate(deliberate, IIdentityRegistry(address(0)));
        uint256 gatedDebateId = _createDebate(deliberate, registry);

        address denied = makeAddr("denied");
        registry.deny(denied);

        vm.prank(denied);
        deliberate.join(openDebateId);

        vm.expectRevert(Deliberate.IdentityProofInvalid.selector);
        vm.prank(denied);
        deliberate.join(gatedDebateId);
    }
}
