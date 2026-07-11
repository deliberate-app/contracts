// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {SlotDerivation} from "@openzeppelin-contracts-5.6.1/utils/SlotDerivation.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {ArborVote} from "../src/ArborVote.sol";
import {IProofOfHumanity} from "../src/interfaces/IProofOfHumanity.sol";

contract ArborVoteStorageTest is Test, ArborVote {
    constructor() ArborVote(IProofOfHumanity(address(0))) {}

    function test_storage_slot() public pure {
        assertEq(_ARBORVOTE_STORAGE_LOCATION, SlotDerivation.erc7201Slot("arborvote.storage.ArborVote"));
    }
}
