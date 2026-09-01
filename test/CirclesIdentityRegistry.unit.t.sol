// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {CirclesIdentityRegistry, ICirclesHub} from "../src/adapters/CirclesIdentityRegistry.sol";
import {MockCirclesHub} from "./mocks/MockCirclesHub.m.sol";

contract CirclesIdentityRegistryTest is Test {
    MockCirclesHub internal _hub;

    address internal _group;
    address internal _member;
    address internal _outsider;

    function setUp() public {
        _hub = new MockCirclesHub();
        _group = makeAddr("group");
        _member = makeAddr("member");
        _outsider = makeAddr("outsider");
    }

    function _registry(address anchor, bool requireHuman) internal returns (CirclesIdentityRegistry registry) {
        registry =
            new CirclesIdentityRegistry({hub: ICirclesHub(address(_hub)), anchor: anchor, requireHuman: requireHuman});
    }

    // --- configuration ---

    function test_constructor_revertsWhenTheGateWouldAdmitEveryone() public {
        // Neither an anchor nor a personhood requirement leaves nothing to check. A debate wanting that is
        // open, and expresses it with the zero registry rather than with a contract that always says yes.
        vm.expectRevert(CirclesIdentityRegistry.RegistryWouldAdmitEveryone.selector);
        _registry(address(0), false);
    }

    // --- personhood, with no anchor ---

    function test_isRegistered_admitsAnyCirclesHumanWhenUnanchored() public {
        CirclesIdentityRegistry registry = _registry(address(0), true);
        _hub.setHuman(_member, true);

        assertTrue(registry.isRegistered(_member));
        assertFalse(registry.isRegistered(_outsider));
    }

    // --- membership, via an anchor's trust ---

    function test_isRegistered_admitsWhoeverTheAnchorTrusts() public {
        // The mode that makes a Circles group reusable as a debate's membership: the adapter reads the trust
        // list the group already maintains, so nothing here has to be curated twice.
        CirclesIdentityRegistry registry = _registry(_group, false);
        _hub.setTrust(_group, _member, true);

        assertTrue(registry.isRegistered(_member));
        assertFalse(registry.isRegistered(_outsider));
    }

    function test_isRegistered_readsTrustInTheDirectionTheAnchorGrantedIt() public {
        // Circles trust is directional. An account trusting the group is not the group admitting the account,
        // and reading it the wrong way round would let anyone admit themselves.
        CirclesIdentityRegistry registry = _registry(_group, false);
        _hub.setTrust(_member, _group, true);

        assertFalse(registry.isRegistered(_member));
    }

    function test_isRegistered_admitsANonHumanAnchoredMemberWhenPersonhoodIsNotRequired() public {
        // Anchored without a personhood requirement, the gate is membership alone - so an organization or a
        // group the anchor trusts is admitted just as a human would be.
        CirclesIdentityRegistry registry = _registry(_group, false);
        _hub.setTrust(_group, _member, true);

        assertFalse(_hub.isHuman(_member));
        assertTrue(registry.isRegistered(_member));
    }

    // --- both conditions ---

    function test_isRegistered_requiresBothWhenAnchoredAndPersonhoodIsRequired() public {
        CirclesIdentityRegistry registry = _registry(_group, true);
        address trustedNonHuman = makeAddr("trustedNonHuman");
        address untrustedHuman = makeAddr("untrustedHuman");

        _hub.setTrust(_group, trustedNonHuman, true);
        _hub.setHuman(untrustedHuman, true);
        _hub.setTrust(_group, _member, true);
        _hub.setHuman(_member, true);

        assertFalse(registry.isRegistered(trustedNonHuman));
        assertFalse(registry.isRegistered(untrustedHuman));
        assertTrue(registry.isRegistered(_member));
    }
}
