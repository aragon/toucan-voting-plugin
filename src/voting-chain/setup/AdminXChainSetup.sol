// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {OAppInitializer} from "@oapp-upgradeable/aragon-oapp/OAppInitializer.sol";
import {AdminXChain} from "@voting-chain/crosschain/AdminXChain.sol";

/// @title AdminXChainSetup
/// @author Aragon X
/// @notice The setup contract of the `AdminXChain` plugin.
/// @custom:security-contact sirt@aragon.org
contract AdminXChainSetup is PluginSetup {
    using ProxyLib for address;

    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    address public immutable adminXChainBase;

    /// @notice The constructor setting the `Admin` implementation contract to clone from.
    constructor(AdminXChain _implementation) PluginSetup() {
        adminXChainBase = address(_implementation);
    }

    function implementation() external view returns (address) {
        return adminXChainBase;
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        address lzEndpoint = abi.decode(_data, (address));

        // Clone and initialize the plugin contract.
        bytes memory initData = abi.encodeCall(AdminXChain.initialize, (_dao, lzEndpoint));
        plugin = adminXChainBase.deployMinimalProxy(initData);

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](3);

        // Grant the DAO OApp admin
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(plugin)).OAPP_ADMINISTRATOR_ID()
        });

        // Grant `EXECUTE_PERMISSION` on the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        // sweep on the DAO
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(plugin)).SWEEP_COLLECTOR_ID()
        });

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](3);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(_payload.plugin)).SWEEP_COLLECTOR_ID()
        });

        // remove OApp Adminstration IDs
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(_payload.plugin)).OAPP_ADMINISTRATOR_ID()
        });
    }
}
