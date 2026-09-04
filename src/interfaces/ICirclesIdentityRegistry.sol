// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ICirclesHub} from "../adapters/CirclesIdentityRegistry.sol";
import {IIdentityRegistry} from "./IIdentityRegistry.sol";

/// @title ICirclesIdentityRegistry
/// @author Michael Heuer
/// @notice The interface of an identity registry that reads the Circles v2 Hub. It admits the accounts
/// that a chosen avatar trusts, the accounts Circles registered as human, or only accounts that are both.
interface ICirclesIdentityRegistry is IIdentityRegistry {
    /// @notice Sets which accounts this registry admits. Callable once.
    /// @param trustAnchor The avatar whose trust admits an account. The zero address admits every account
    /// Circles registered as a human instead.
    /// @param humanRequired Whether an admitted account must also be a registered human.
    function initialize(address trustAnchor, bool humanRequired) external;

    /// @notice Returns the Circles Hub this registry reads.
    /// @return circlesHub The Hub.
    function hub() external view returns (ICirclesHub circlesHub);

    /// @notice Returns the avatar whose trust admits an account.
    /// @return avatar The anchor, or the zero address where any Circles human is admitted.
    function anchor() external view returns (address avatar);

    /// @notice Returns whether an admitted account must also be a registered human.
    /// @return required Whether personhood is required.
    function requireHuman() external view returns (bool required);
}
