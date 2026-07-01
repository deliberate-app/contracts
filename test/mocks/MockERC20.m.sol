// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 initialSupply, address beneficiary) ERC20("Mock ERC20 Token", "MCK") {
        _mint(beneficiary, initialSupply);
    }
}
