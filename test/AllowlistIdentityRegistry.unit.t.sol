// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Clones} from "@openzeppelin-contracts-5.6.1/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable-5.6.1/access/OwnableUpgradeable.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {AllowlistIdentityRegistry} from "../src/adapters/AllowlistIdentityRegistry.sol";
import {IAllowlistIdentityRegistry} from "../src/interfaces/IAllowlistIdentityRegistry.sol";

contract AllowlistIdentityRegistryTest is Test {
    AllowlistIdentityRegistry internal _registry;

    address internal _owner;
    address internal _alice;
    address internal _bob;

    function setUp() public {
        _owner = makeAddr("owner");
        _alice = makeAddr("alice");
        _bob = makeAddr("bob");
        // A registry is a clone of one implementation in practice, so the tests read one.
        _registry = AllowlistIdentityRegistry(Clones.clone(address(new AllowlistIdentityRegistry())));
        _registry.initialize(_owner);
    }

    function _setMembership(address account, bool member) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        vm.prank(_owner);
        _registry.setMembership(accounts, member);
    }

    function test_isRegistered_isFalseBeforeAnyoneIsAdded() public view {
        assertFalse(_registry.isRegistered(_alice));
    }

    function test_setMembership_addsAndRemovesMembers() public {
        _setMembership(_alice, true);
        _setMembership(_bob, true);
        assertTrue(_registry.isRegistered(_alice));
        assertTrue(_registry.isRegistered(_bob));

        _setMembership(_alice, false);
        assertFalse(_registry.isRegistered(_alice));
        assertTrue(_registry.isRegistered(_bob));
    }

    function test_setMembership_setsSeveralAccountsInOneCall() public {
        address[] memory accounts = new address[](2);
        accounts[0] = _alice;
        accounts[1] = _bob;

        vm.prank(_owner);
        _registry.setMembership(accounts, true);

        assertTrue(_registry.isRegistered(_alice));
        assertTrue(_registry.isRegistered(_bob));
    }

    function test_setMembership_emitsMembershipSetPerAccount() public {
        address[] memory accounts = new address[](2);
        accounts[0] = _alice;
        accounts[1] = _bob;

        vm.expectEmit();
        emit IAllowlistIdentityRegistry.MembershipSet({account: _alice, member: true});
        vm.expectEmit();
        emit IAllowlistIdentityRegistry.MembershipSet({account: _bob, member: true});

        vm.prank(_owner);
        _registry.setMembership(accounts, true);
    }

    function test_setMembership_revertsForAnyoneButTheOwner() public {
        // The owner is the whole trust model here, so the boundary is the contract's only real guarantee.
        address[] memory accounts = new address[](1);
        accounts[0] = _alice;

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, _alice));
        vm.prank(_alice);
        _registry.setMembership(accounts, true);
    }
}
