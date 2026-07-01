// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/ERC20.sol";

import {IArbitrator} from "../../src/interfaces/IArbitrator.sol";
import {MockERC20} from "./MockERC20.m.sol";

contract MockArbitrator is IArbitrator {
    MockERC20 private _token;

    // solhint-disable-next-line no-empty-blocks
    function submitEvidence(uint256 disputeId, address submitter, bytes calldata evidence) external {}

    // solhint-disable-next-line no-empty-blocks
    function closeEvidencePeriod(uint256 disputeId) external {}

    function getDisputeFees() external view returns (address recipient, ERC20 feeToken, uint256 feeAmount) {
        recipient = address(0);
        feeToken = _token;
        feeAmount = 123;
    }

    function createDispute(uint256 possibleRulings, bytes calldata metadata) external pure returns (uint256 disputeId) {
        (possibleRulings, metadata);
        disputeId = 0;
    }

    function rule(uint256 disputeId) external pure returns (address subject, uint256 ruling) {
        (disputeId);
        subject = address(0);
        ruling = 0;
    }

    function getPaymentsRecipient() external pure returns (address recipient) {
        recipient = address(0);
    }
}
