// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";
import {Vm} from "forge-std-1.16.1/src/Vm.sol";

import {AllowlistIdentityRegistry} from "../src/adapters/AllowlistIdentityRegistry.sol";
import {CirclesIdentityRegistry, ICirclesHub} from "../src/adapters/CirclesIdentityRegistry.sol";
import {IdentityRegistryFactory} from "../src/IdentityRegistryFactory.sol";
import {IAllowlistIdentityRegistry} from "../src/interfaces/IAllowlistIdentityRegistry.sol";
import {ICirclesIdentityRegistry} from "../src/interfaces/ICirclesIdentityRegistry.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {IIdentityRegistryFactory} from "../src/interfaces/IIdentityRegistryFactory.sol";
import {MockCirclesHub} from "./mocks/MockCirclesHub.m.sol";

contract IdentityRegistryFactoryTest is Test {
    IdentityRegistryFactory internal _factory;
    MockCirclesHub internal _hub;

    address internal _owner;
    address internal _other;
    address internal _human;

    function setUp() public {
        _hub = new MockCirclesHub();
        _factory = new IdentityRegistryFactory(ICirclesHub(address(_hub)));
        _owner = makeAddr("owner");
        _other = makeAddr("other");
        _human = makeAddr("human");
    }

    function _setMembership(address registry, address account, bool member) internal {
        address[] memory accounts = new address[](1);
        accounts[0] = account;
        IAllowlistIdentityRegistry(registry).setMembership(accounts, member);
    }

    // --- allowlist registries ---

    function test_createAllowlistRegistry_handsTheRegistryToItsOwner() public {
        address registry = _factory.createAllowlistRegistry(_owner);

        vm.prank(_owner);
        _setMembership(registry, _human, true);

        assertTrue(IIdentityRegistry(registry).isRegistered(_human));
    }

    function test_createAllowlistRegistry_emitsTheCreation() public {
        // The address is known only after the call, so the log is read back rather than expected.
        vm.recordLogs();
        address registry = _factory.createAllowlistRegistry(_owner);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        Vm.Log memory announced = logs[logs.length - 1];

        assertEq(announced.emitter, address(_factory));
        assertEq(announced.topics[0], IIdentityRegistryFactory.AllowlistRegistryCreated.selector);
        assertEq(address(uint160(uint256(announced.topics[1]))), registry);
        assertEq(address(uint160(uint256(announced.topics[2]))), _owner);
    }

    function test_createAllowlistRegistry_givesEachRegistryItsOwnMembership() public {
        address first = _factory.createAllowlistRegistry(_owner);
        address second = _factory.createAllowlistRegistry(_other);

        vm.prank(_owner);
        _setMembership(first, _human, true);

        assertTrue(IIdentityRegistry(first).isRegistered(_human));
        assertFalse(IIdentityRegistry(second).isRegistered(_human));
    }

    function test_createAllowlistRegistry_leavesEveryOtherAccountOut() public {
        address registry = _factory.createAllowlistRegistry(_owner);

        vm.prank(_other);
        vm.expectRevert();
        _setMembership(registry, _other, true);
    }

    // --- Circles registries ---

    function test_createCirclesRegistry_gatesOnTheFactorysHub() public {
        address registry = _factory.createCirclesRegistry({anchor: address(0), requireHuman: true});
        _hub.setHuman(_human, true);

        assertEq(address(ICirclesIdentityRegistry(registry).hub()), address(_hub));
        assertTrue(IIdentityRegistry(registry).isRegistered(_human));
        assertFalse(IIdentityRegistry(registry).isRegistered(_other));
    }

    function test_createCirclesRegistry_givesEachRegistryItsOwnGate() public {
        address anyHuman = _factory.createCirclesRegistry({anchor: address(0), requireHuman: true});
        address trusted = _factory.createCirclesRegistry({anchor: _owner, requireHuman: false});
        _hub.setHuman(_human, true);
        _hub.setTrust({truster: _owner, trustee: _other, trusted: true});

        assertEq(ICirclesIdentityRegistry(anyHuman).anchor(), address(0));
        assertEq(ICirclesIdentityRegistry(trusted).anchor(), _owner);
        assertTrue(IIdentityRegistry(anyHuman).isRegistered(_human));
        assertFalse(IIdentityRegistry(anyHuman).isRegistered(_other));
        assertTrue(IIdentityRegistry(trusted).isRegistered(_other));
        assertFalse(IIdentityRegistry(trusted).isRegistered(_human));
    }

    function test_createCirclesRegistry_revertsWhenTheGateWouldAdmitEveryone() public {
        vm.expectRevert(CirclesIdentityRegistry.RegistryWouldAdmitEveryone.selector);
        _factory.createCirclesRegistry({anchor: address(0), requireHuman: false});
    }

    // --- the implementations behind the clones ---

    function test_createRegistry_reusesOneImplementationPerShape() public {
        address first = _factory.createAllowlistRegistry(_owner);
        address second = _factory.createAllowlistRegistry(_other);

        assertNotEq(first, second);
        assertEq(first.code.length, second.code.length); // an EIP-1167 proxy, not a full deployment
        assertLt(first.code.length, _factory.allowlistImplementation().code.length);
    }

    function test_implementation_cannotBeInitialized() public {
        // An implementation anyone could initialize is an allowlist anyone could own.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        AllowlistIdentityRegistry(_factory.allowlistImplementation()).initialize(_other);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        CirclesIdentityRegistry(_factory.circlesImplementation()).initialize({
            trustAnchor: address(0), humanRequired: true
        });
    }

    function test_registry_cannotBeInitializedTwice() public {
        address registry = _factory.createAllowlistRegistry(_owner);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        AllowlistIdentityRegistry(registry).initialize(_other);
    }
}
