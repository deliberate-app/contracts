// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin-contracts-upgradeable-5.6.1/proxy/utils/Initializable.sol";
import {IHubV2} from "circles-contracts-v2-0.3.6/src/hub/IHub.sol";

import {ICirclesIdentityRegistry} from "../interfaces/ICirclesIdentityRegistry.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";

/// @title ICirclesHub
/// @author Michael Heuer
/// @notice The Circles v2 Hub as this adapter reads it. It adds `isTrusted` to `IHubV2` from Circles.
/// Circles declares `isTrusted` on the Hub contract but not on its interface.
interface ICirclesHub is IHubV2 {
    /// @notice Returns whether the truster's trust in the trustee is currently valid.
    /// @param truster The trusting avatar.
    /// @param trustee The trusted address.
    /// @return trusted Whether the trust is set and unexpired.
    function isTrusted(address truster, address trustee) external view returns (bool trusted);
}

/// @title CirclesIdentityRegistry
/// @author Michael Heuer
/// @notice An identity registry on the Circles v2 Hub. It admits every account Circles registered as a
/// human, or the accounts that a chosen avatar trusts. Clones share the Hub in code, and each clone holds
/// its own anchor and personhood setting in storage.
/// @dev Circles personhood is a social invite graph, not a proof of personhood. `isHuman` stays true after
/// an avatar stops minting.
contract CirclesIdentityRegistry is ICirclesIdentityRegistry, Initializable {
    /// @notice The Circles v2 Hub. One per chain, so it is fixed for every clone of this implementation.
    ICirclesHub internal immutable _HUB;

    /// @notice The avatar whose trust admits an account. The zero address admits every registered human.
    address internal _anchor;

    /// @notice Whether an admitted account must additionally be a registered human.
    bool internal _requireHuman;

    /// @notice Thrown when the registry has neither an anchor nor a personhood requirement. Such a
    /// registry would admit every address. A debate that wants this names the zero registry instead.
    error RegistryWouldAdmitEveryone();

    /// @notice Binds the implementation to one Circles Hub. Every clone of it reads that Hub.
    /// @param circlesHub The Circles v2 Hub every clone of this implementation reads.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(ICirclesHub circlesHub) {
        _HUB = circlesHub;
        _disableInitializers();
    }

    /// @notice Sets which accounts this registry admits. The factory calls this on a new clone, and no
    /// later call can change what the registry admits.
    /// @param trustAnchor The avatar whose trust admits an account. The zero address admits every account
    /// Circles registered as a human instead.
    /// @param humanRequired Whether an admitted account must also be a registered human.
    function initialize( /* solhint-disable-line comprehensive-interface*/
        address trustAnchor,
        bool humanRequired
    )
        external
        initializer
    {
        if (trustAnchor == address(0) && !humanRequired) {
            revert RegistryWouldAdmitEveryone();
        }

        _anchor = trustAnchor;
        _requireHuman = humanRequired;
    }

    /// @inheritdoc IIdentityRegistry
    function isRegistered(address account) external view override returns (bool registered) {
        address trustAnchor = _anchor;
        if (trustAnchor != address(0) && !_HUB.isTrusted({truster: trustAnchor, trustee: account})) {
            return false;
        }
        if (_requireHuman && !_HUB.isHuman(account)) {
            return false;
        }

        registered = true;
    }

    /// @inheritdoc ICirclesIdentityRegistry
    function hub() external view override returns (ICirclesHub circlesHub) {
        circlesHub = _HUB;
    }

    /// @inheritdoc ICirclesIdentityRegistry
    function anchor() external view override returns (address avatar) {
        avatar = _anchor;
    }

    /// @inheritdoc ICirclesIdentityRegistry
    function requireHuman() external view override returns (bool required) {
        required = _requireHuman;
    }
}
