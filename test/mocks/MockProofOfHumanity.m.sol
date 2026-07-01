// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IProofOfHumanity} from "../../src/interfaces/IProofOfHumanity.sol";

contract MockProofOfHumanity is IProofOfHumanity {
    mapping(address account => bool isDenied) public denyList;

    function deny(address account) external {
        denyList[account] = true;
    }

    function isRegistered(address submissionID) external view returns (bool registered) {
        registered = !denyList[submissionID];
    }

    function submissionCounter() external pure returns (uint256 count) {
        count = 1;
    }
}
