// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAttestationIndexer, IEAS} from "../../src/adapters/EASIdentityRegistry.sol";

contract MockEAS is IEAS {
    mapping(bytes32 uid => Attestation attestation) internal _attestations;

    function setAttestation(Attestation calldata attestation) external {
        _attestations[attestation.uid] = attestation;
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory attestation) {
        attestation = _attestations[uid];
    }
}

contract MockAttestationIndexer is IAttestationIndexer {
    mapping(address recipient => mapping(bytes32 schemaUid => bytes32 attestationUid)) internal _attestationUids;

    function setAttestationUid(address recipient, bytes32 schemaUid, bytes32 attestationUid) external {
        _attestationUids[recipient][schemaUid] = attestationUid;
    }

    function getAttestationUid(address recipient, bytes32 schemaUid) external view returns (bytes32 attestationUid) {
        attestationUid = _attestationUids[recipient][schemaUid];
    }
}
