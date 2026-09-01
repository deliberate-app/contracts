// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

import {ICirclesHub} from "../../src/adapters/CirclesIdentityRegistry.sol";

/// @dev The two Circles Hub reads the adapter makes, scriptable per address. The real Hub derives both from
/// avatar bookkeeping the adapter never touches, so reproducing that bookkeeping here would test Circles
/// rather than the adapter.
contract MockCirclesHub is ICirclesHub {
    mapping(address avatar => bool human) internal _humans;
    mapping(address truster => mapping(address trustee => bool trusted)) internal _trust;

    function setHuman(address avatar, bool human) external {
        _humans[avatar] = human;
    }

    function setTrust(address truster, address trustee, bool trusted) external {
        _trust[truster][trustee] = trusted;
    }

    /// @inheritdoc ICirclesHub
    function isHuman(address avatar) external view override returns (bool human) {
        human = _humans[avatar];
    }

    /// @inheritdoc ICirclesHub
    function isTrusted(address truster, address trustee) external view override returns (bool trusted) {
        trusted = _trust[truster][trustee];
    }
}
