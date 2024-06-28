// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.8;

import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {AdminXChain} from "@voting-chain/crosschain/AdminXChain.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

/// @title AdminXChainSetup
/// @author Aragon X
/// @notice The setup contract of the `AdminXChain` plugin.
/// @custom:security-contact sirt@aragon.org
contract AdminXChainSetup is PluginSetup {
    using ProxyLib for address;

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The address of the `AdminXChain` implementation contract.
    address private immutable adminXChainBase;

    /// @notice The constructor setting the `Admin` implementation contract to clone from.
    constructor(AdminXChain _implementation) PluginSetup() {
        adminXChainBase = address(_implementation);
    }

    /// @return The address of the `AdminXChain` implementation.
    function implementation() external view returns (address) {
        return adminXChainBase;
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        address lzEndpoint = abi.decode(_data, (address));

        // initialize the plugin contract.
        bytes memory initData = abi.encodeCall(AdminXChain.initialize, (_dao, lzEndpoint));
        plugin = adminXChainBase.deployUUPSProxy(initData);

        // no helpers but prepare the permissions.
        preparedSetupData.permissions = getPermissions(
            _dao,
            payable(plugin),
            PermissionLib.Operation.Grant
        );
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = getPermissions(
            _dao,
            payable(_payload.plugin),
            PermissionLib.Operation.Revoke
        );
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin proxy address.
    /// @param _grantOrRevoke The operation to perform.
    function getPermissions(
        address _dao,
        address payable _plugin,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](3);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            where: _plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(_plugin).OAPP_ADMINISTRATOR_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            where: _dao,
            who: _plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            where: _plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(_plugin).SWEEP_COLLECTOR_ID()
        });

        return permissions;
    }
}
