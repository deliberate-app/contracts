// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.24;

/// @dev The two Circles Hub reads the adapter makes, scriptable per address. The real Hub derives both from
/// avatar bookkeeping the adapter never touches, so reproducing that bookkeeping here would test Circles
/// rather than the adapter. Not declared as `ICirclesHub`: that interface now extends the protocol's own
/// `IHubV2`, whose ERC-1155 and demurrage surface has nothing to do with the gate, and the tests hand this
/// mock over by address anyway.
contract MockCirclesHub {
    mapping(address avatar => bool human) internal _humans;
    mapping(address truster => mapping(address trustee => bool trusted)) internal _trust;

    function setHuman(address avatar, bool human) external {
        _humans[avatar] = human;
    }

    function setTrust(address truster, address trustee, bool trusted) external {
        _trust[truster][trustee] = trusted;
    }

    function isHuman(address avatar) external view returns (bool human) {
        human = _humans[avatar];
    }

    function isTrusted(address truster, address trustee) external view returns (bool trusted) {
        trusted = _trust[truster][trustee];
    }
}
