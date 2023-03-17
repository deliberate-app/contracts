//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IProofOfHumanity.sol";

contract MockProofOfHumanity is IProofOfHumanity {
    mapping(address => bool) public denyList;

    function deny(address _account) external {
        denyList[_account] = true;
    }

    function isRegistered(address _submissionID) external view returns (bool) {
        return !denyList[_submissionID];
    }

    function submissionCounter() external pure returns (uint256) {
        return 1;
    }
}
