// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.17;

import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup, PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import {ArborVote} from "./ArborVote.sol";

import {IProofOfHumanity} from "./interfaces/IProofOfHumanity.sol";

contract ArborVoteSetup is PluginSetup {
    address internal pluginBase;

    constructor() {
        pluginBase = address(new ArborVote());
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes memory _data
    ) public virtual override returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `Multisig` plugin.
        address ipoh = abi.decode(_data, (address));

        plugin = createERC1967Proxy(
            address(pluginBase),
            abi.encodeWithSelector(ArborVote.initialize.selector, IProofOfHumanity(ipoh))
        );
        //preparedSetupData.helpers =
        //preparedSetupData.permissions =
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external virtual override returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        (_dao, _payload);
        //permissions =
    }

    /// @inheritdoc IPluginSetup
    function implementation() external view virtual override returns (address) {
        return address(pluginBase);
    }
}
