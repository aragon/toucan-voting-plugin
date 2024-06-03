// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {AdminXChain as Admin} from "../crosschain/AdminXChain.sol";

/// @title AdminAddressSetup
/// @author Aragon X
/// @notice The setup contract of the `AdminXChain` plugin.
/// @custom:security-contact sirt@aragon.org
contract AdminSetup is PluginSetup {
    using ProxyLib for address;

    // TODO This permission identifier has to be moved inside `PermissionLib` as per task OS-954.
    /// @notice The ID of the permission required to call the `execute` function.
    bytes32 internal constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice Thrown if the admin address is zero.
    /// @param admin The admin address.
    error AdminAddressInvalid(address admin);

    /// @notice The constructor setting the `Admin` implementation contract to clone from.
    constructor() PluginSetup(address(new Admin())) {}

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for cloning and initializing the `Admin` plugin.
        address admin = abi.decode(_data, (address));

        if (admin == address(0)) {
            revert AdminAddressInvalid({admin: admin});
        }

        // Clone and initialize the plugin contract.
        bytes memory initData = abi.encodeCall(Admin.initialize, (IDAO(_dao)));
        plugin = IMPLEMENTATION.deployMinimalProxy(initData);

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](2);

        // Grant `ADMIN_EXECUTE_PERMISSION` of the plugin to the admin.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: admin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: Admin(plugin).EXECUTE_PROPOSAL_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` on the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    /// @dev Currently, there is no reliable way to revoke the `ADMIN_EXECUTE_PERMISSION_ID` from all addresses
    /// it has been granted to. Accordingly, only the `EXECUTE_PERMISSION_ID` is revoked for this uninstallation.
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions
        permissions = new PermissionLib.MultiTargetPermission[](1);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });
    }
}
