// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {Deliberate} from "../src/Deliberate.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {Parameters} from "../src/libs/Parameters.sol";
import {DebateGen} from "./libs/DebateGen.sol";

// Gas benchmarks for the atomic tally. It settles a whole tree in one transaction and is the only route to a
// finished debate, so a tree it cannot settle is a tree whose deposits and bounty are locked for ever. The bound
// is the tightest chain the protocol targets, half a Gnosis block, so that a full tally is comfortably includable
// there. The measurements only mean anything against the shipped, optimized build: the coverage run, an
// unoptimized instrumented build, leaves this file out by path.
contract DeliberateGasTest is Test {
    using DebateGen for Vm;

    uint256 internal constant _GNOSIS_BLOCK_GAS_LIMIT = 17_000_000;
    uint16 internal constant _ROOT_ARGUMENT_ID = 0;

    Deliberate internal _deliberate;

    function setUp() public {
        _deliberate = new Deliberate();
    }

    function _createDebate(uint48 lockingDuration, uint48 editingDuration, uint48 ratingDuration)
        internal
        returns (DebateGen.Debate memory debate)
    {
        uint256 debateId = _deliberate.createDebate({
            content: "We should do XYZ",
            lockingDuration: lockingDuration,
            editingDuration: editingDuration,
            ratingDuration: ratingDuration,
            feePercentage: 5,
            identityRegistry: IIdentityRegistry(address(0)),
            bountyToken: IERC20(address(0)),
            bountyAmount: 0
        });
        debate = DebateGen.Debate({deliberate: _deliberate, id: debateId});
    }

    function _tallyGas(DebateGen.Debate memory debate) internal returns (uint256 gasUsed) {
        vm.warpToTallying(debate);
        uint256 gasBefore = gasleft();
        vm.tally(debate);
        gasUsed = gasBefore - gasleft();
    }

    function test_tallyTree_staysWithinTheBlockGasLimitAtTheArgumentCap() public {
        // Every argument a child of the thesis. By the Tallying phase all of them are final and carry sway - the
        // expensive path.
        DebateGen.Debate memory debate =
            _createDebate({lockingDuration: 1 minutes, editingDuration: 7 minutes, ratingDuration: 3 minutes});
        vm.fan(debate, _ROOT_ARGUMENT_ID, Parameters.MAX_ARGUMENTS - 1);

        assertLt(_tallyGas(debate), _GNOSIS_BLOCK_GAS_LIMIT / 2);
    }

    function test_tallyTree_staysWithinTheBlockGasLimitAtTheDeepestChain() public {
        // The cap bounds the tree's size, not its shape, and the deepest reachable shape is a single chain: depth
        // costs one locking window per level, which the creator sets. The tally walks from the single leaf to the
        // root and must fit the budget the flat tree does - the shape may not decide whether a debate settles.
        DebateGen.Debate memory debate = _createDebate({
            lockingDuration: 1, editingDuration: 4 * uint48(Parameters.MAX_ARGUMENTS), ratingDuration: 100
        });
        vm.chain(debate, _ROOT_ARGUMENT_ID, Parameters.MAX_ARGUMENTS - 1);

        assertLt(_tallyGas(debate), _GNOSIS_BLOCK_GAS_LIMIT / 2);
    }
}
