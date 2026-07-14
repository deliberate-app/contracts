// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

// A plain mintable ERC-20 for bounty tests.
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// A fee-on-transfer ERC-20 burning 10% of every real transfer - the receiver gets less than
// was sent, so bounty funding must record the received amount, not the sent one.
contract MockERC20FeeOnTransfer is ERC20 {
    constructor() ERC20("Fee Token", "FEE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = value / 10;
            super._update(from, address(0), fee);
            value -= fee;
        }
        super._update(from, to, value);
    }
}
