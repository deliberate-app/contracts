// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Test} from "forge-std-1.16.1/src/Test.sol";

import {EASIdentityRegistry, IAttestationIndexer, IEAS} from "../src/adapters/EASIdentityRegistry.sol";
import {MockAttestationIndexer, MockEAS} from "./mocks/MockEAS.m.sol";

contract EASIdentityRegistryTest is Test {
    bytes32 internal constant _SCHEMA_UID = keccak256("verified-account");
    bytes32 internal constant _UID = keccak256("attestation");

    address internal immutable _ATTESTER = makeAddr("attester");
    address internal immutable _ACCOUNT = makeAddr("account");

    MockEAS internal _eas;
    MockAttestationIndexer internal _indexer;
    EASIdentityRegistry internal _registry;

    function setUp() external {
        _eas = new MockEAS();
        _indexer = new MockAttestationIndexer();
        _registry = new EASIdentityRegistry({
            eas: IEAS(address(_eas)),
            indexer: IAttestationIndexer(address(_indexer)),
            schemaUid: _SCHEMA_UID,
            attester: _ATTESTER
        });
    }

    // A fully valid attestation for the queried account; tests break one field at a time.
    function _validAttestation() internal view returns (IEAS.Attestation memory attestation) {
        attestation = IEAS.Attestation({
            uid: _UID,
            schema: _SCHEMA_UID,
            time: uint64(vm.getBlockTimestamp()),
            expirationTime: 0,
            revocationTime: 0,
            refUID: bytes32(0),
            recipient: _ACCOUNT,
            attester: _ATTESTER,
            revocable: true,
            data: ""
        });
    }

    // Stores the attestation and wires the indexer lookup the adapter performs for the queried account.
    function _store(IEAS.Attestation memory attestation) internal {
        _eas.setAttestation(attestation);
        _indexer.setAttestationUid({recipient: _ACCOUNT, schemaUid: _SCHEMA_UID, attestationUid: attestation.uid});
    }

    function test_constructor_rejectsAZeroAttester() external {
        vm.expectRevert(EASIdentityRegistry.AttesterZero.selector);
        new EASIdentityRegistry({
            eas: IEAS(address(_eas)),
            indexer: IAttestationIndexer(address(_indexer)),
            schemaUid: _SCHEMA_UID,
            attester: address(0)
        });
    }

    function test_isRegistered_acceptsAValidAttestation() external {
        _store(_validAttestation());

        assertTrue(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_rejectsAnAccountWithoutAnAttestation() external view {
        assertFalse(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_rejectsAForeignAttester() external {
        IEAS.Attestation memory attestation = _validAttestation();
        attestation.attester = makeAddr("impostor");
        _store(attestation);

        assertFalse(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_rejectsARevokedAttestation() external {
        IEAS.Attestation memory attestation = _validAttestation();
        attestation.revocationTime = uint64(vm.getBlockTimestamp());
        _store(attestation);

        assertFalse(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_expiresWithTheAttestation() external {
        IEAS.Attestation memory attestation = _validAttestation();
        attestation.expirationTime = uint64(vm.getBlockTimestamp() + 1 days);
        _store(attestation);

        assertTrue(_registry.isRegistered(_ACCOUNT));

        skip(1 days);
        assertFalse(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_rejectsAMismatchedSchema() external {
        IEAS.Attestation memory attestation = _validAttestation();
        attestation.schema = keccak256("some-other-schema");
        _store(attestation);

        assertFalse(_registry.isRegistered(_ACCOUNT));
    }

    function test_isRegistered_rejectsAMismatchedRecipient() external {
        IEAS.Attestation memory attestation = _validAttestation();
        attestation.recipient = makeAddr("someone-else");
        _store(attestation);

        assertFalse(_registry.isRegistered(_ACCOUNT));
    }
}
