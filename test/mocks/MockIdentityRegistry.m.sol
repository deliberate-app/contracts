// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";

contract MockIdentityRegistry is IIdentityRegistry {
    mapping(address account => bool isDenied) public denyList;

    function deny(address account) external {
        denyList[account] = true;
    }

    function isRegistered(address account) external view returns (bool registered) {
        registered = !denyList[account];
    }
}
