// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";

import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title IEAS
/// @author Michael Heuer
/// @notice The minimal read subset of the Ethereum Attestation Service (the EAS predeploy
/// 0x4200000000000000000000000000000000000021 on OP-stack chains such as Base). The struct must match
/// the layout of EAS' `Common.sol` exactly for the external call to decode.
interface IEAS {
    /// @notice An attestation as stored by EAS.
    struct Attestation {
        bytes32 uid;
        bytes32 schema;
        uint64 time;
        uint64 expirationTime;
        uint64 revocationTime;
        bytes32 refUID;
        address recipient;
        address attester;
        bool revocable;
        bytes data;
    }

    /// @notice Returns an attestation by its UID (a zeroed struct if unknown).
    /// @param uid The attestation UID.
    /// @return attestation The attestation.
    function getAttestation(bytes32 uid) external view returns (Attestation memory attestation);
}

/// @title IAttestationIndexer
/// @author Michael Heuer
/// @notice The minimal read subset of an attestation indexer resolving a recipient and schema to the
/// latest attestation UID (e.g. the Indexer contract published by Coinbase Verifications).
interface IAttestationIndexer {
    /// @notice Returns the latest attestation UID for a recipient under a schema (zero if none).
    /// @param recipient The attested account.
    /// @param schemaUid The attestation schema UID.
    /// @return attestationUid The attestation UID.
    function getAttestationUid(address recipient, bytes32 schemaUid) external view returns (bytes32 attestationUid);
}

/// @title EASIdentityRegistry
/// @author Michael Heuer
/// @notice A reference identity-registry adapter over Ethereum Attestation Service attestations: an
/// account is registered while it holds an unrevoked, unexpired attestation of the configured schema
/// issued by the configured attester. This fits externally operated KYC registries such as Coinbase
/// Verifications on Base ("Verified Account" schema) - verify the EAS, indexer, schema UID, and
/// attester values against the provider's official publications before deploying, and mind that
/// address deduplication is only as strong as the provider's per-identity address policy.
contract EASIdentityRegistry is IIdentityRegistry {
    /// @notice The Ethereum Attestation Service contract.
    IEAS internal immutable _EAS;

    /// @notice The indexer resolving (recipient, schema) to the latest attestation UID.
    IAttestationIndexer internal immutable _INDEXER;

    /// @notice The attestation schema UID accepted as an identity proof.
    bytes32 internal immutable _SCHEMA_UID;

    /// @notice The sole attester whose attestations are accepted.
    address internal immutable _ATTESTER;

    /// @notice Thrown when the attester is the zero address (an unknown attestation UID decodes to a
    /// zeroed attestation, so a zero attester must never be accepted).
    error AttesterZero();

    /// @notice Deploys the adapter for one (attester, schema) pair on one EAS deployment.
    /// @param eas The Ethereum Attestation Service contract.
    /// @param indexer The attestation indexer.
    /// @param schemaUid The attestation schema UID accepted as an identity proof.
    /// @param attester The sole attester whose attestations are accepted.
    constructor(IEAS eas, IAttestationIndexer indexer, bytes32 schemaUid, address attester) {
        if (attester == address(0)) {
            revert AttesterZero();
        }

        _EAS = eas;
        _INDEXER = indexer;
        _SCHEMA_UID = schemaUid;
        _ATTESTER = attester;
    }

    /// @inheritdoc IIdentityRegistry
    function isRegistered(address account) external view override returns (bool registered) {
        bytes32 uid = _INDEXER.getAttestationUid({recipient: account, schemaUid: _SCHEMA_UID});
        if (uid == bytes32(0)) {
            return false;
        }

        IEAS.Attestation memory attestation = _EAS.getAttestation(uid);

        registered = attestation.attester == _ATTESTER && attestation.schema == _SCHEMA_UID
            && attestation.recipient == account && attestation.revocationTime == 0
            && (attestation.expirationTime == 0 || attestation.expirationTime > Time.timestamp());
    }
}
