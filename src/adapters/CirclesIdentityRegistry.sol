// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title ICirclesHub
/// @author Michael Heuer
/// @notice The minimal read subset of the Circles v2 Hub on Gnosis. Circles registers avatars as humans,
/// groups or organizations, and lets any avatar extend expiring, directional trust to any address.
interface ICirclesHub {
    /// @notice Returns whether an avatar is registered as a human.
    /// @param avatar The address to check.
    /// @return human Whether the avatar is a registered human.
    function isHuman(address avatar) external view returns (bool human);

    /// @notice Returns whether the truster's trust in the trustee is currently valid.
    /// @param truster The trusting avatar.
    /// @param trustee The trusted address.
    /// @return trusted Whether the trust is set and unexpired.
    function isTrusted(address truster, address trustee) external view returns (bool trusted);
}

/// @title CirclesIdentityRegistry
/// @author Michael Heuer
/// @notice An identity-registry adapter over the Circles v2 Hub, covering both shapes a debate creator
/// might want from Circles with one contract.
///
/// With no anchor it registers any Circles human, using the protocol's invite graph as a personhood proxy.
/// With an anchor it registers whoever that avatar currently trusts - and since a Circles group already
/// maintains exactly such a member list in the protocol's own tooling, a creator can gate a debate on a
/// membership they curate elsewhere without deploying or maintaining anything here. The anchor may be any
/// avatar: a group, an organization, or a single human vouching for others.
///
/// Two properties are worth knowing before relying on it. Circles personhood is a social invite graph, not
/// a proof of personhood - it raises the cost of sybils rather than ruling them out. And `isHuman` stays
/// true for an avatar that has stopped minting, because stopping sets the mint time to the indefinite
/// future rather than clearing it.
contract CirclesIdentityRegistry is IIdentityRegistry {
    /// @notice The Circles v2 Hub.
    ICirclesHub internal immutable _HUB;

    /// @notice The avatar whose trust admits an account, or the zero address to admit any Circles human.
    address internal immutable _ANCHOR;

    /// @notice Whether an admitted account must additionally be a registered human.
    bool internal immutable _REQUIRE_HUMAN;

    /// @notice Thrown when neither an anchor nor a personhood requirement is configured, which would
    /// register every address. A debate wanting that is open, and says so with the zero registry.
    error RegistryWouldAdmitEveryone();

    /// @notice Deploys the adapter for one gate on one Circles Hub.
    /// @param hub The Circles v2 Hub.
    /// @param anchor The avatar whose trust admits an account; the zero address admits any Circles human.
    /// @param requireHuman Whether an anchored account must also be a registered human.
    constructor(ICirclesHub hub, address anchor, bool requireHuman) {
        if (anchor == address(0) && !requireHuman) {
            revert RegistryWouldAdmitEveryone();
        }

        _HUB = hub;
        _ANCHOR = anchor;
        _REQUIRE_HUMAN = requireHuman;
    }

    /// @inheritdoc IIdentityRegistry
    function isRegistered(address account) external view override returns (bool registered) {
        if (_ANCHOR != address(0) && !_HUB.isTrusted({truster: _ANCHOR, trustee: account})) {
            return false;
        }
        if (_REQUIRE_HUMAN && !_HUB.isHuman(account)) {
            return false;
        }

        registered = true;
    }
}
