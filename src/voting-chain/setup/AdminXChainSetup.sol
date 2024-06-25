// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

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

    /// @notice A single use initializer that will allow peers to be set after setup.
    address immutable initalizerBase;

    /// @notice The constructor setting the `Admin` implementation contract to clone from.
    constructor(OAppInitializer _initializerBase) PluginSetup(address(new AdminXChain())) {
        initalizerBase = address(_initializerBase);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        (address lzEndpoint, address initializeCaller) = abi.decode(_data, (address, address));

        // Clone and initialize the plugin contract.
        bytes memory initData = abi.encodeCall(AdminXChain.initialize, (_dao, lzEndpoint));
        plugin = IMPLEMENTATION.deployMinimalProxy(initData);

        // set peer needs to be called when the corresponding receiver is deployed on the execution chain
        // for this we deploy a contract that will allow an address outside of the dao to call setPeer once
        // which is then unable to be called again
        address initializer = initalizerBase.deployMinimalProxy(abi.encode(_dao, plugin));

        address[] memory helpers = new address[](1);
        helpers[0] = initializer;

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](5);

        // Grant the DAO OApp admin
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(plugin)).OAPP_ADMINISTRATOR_ID()
        });

        // also give it to the initializer
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: initializer,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(plugin)).OAPP_ADMINISTRATOR_ID()
        });

        // give the initializeCaller the ability to call the set peer
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: initializer,
            who: initializeCaller,
            condition: PermissionLib.NO_CONDITION,
            permissionId: OAppInitializer(initializer).INITIALIZER_ID()
        });

        // Grant `EXECUTE_PERMISSION` on the DAO to the plugin.
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        // sweep on the DAO
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: AdminXChain(payable(plugin)).SWEEP_COLLECTOR_ID()
        });

        preparedSetupData.permissions = permissions;
        preparedSetupData.helpers = helpers;
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
