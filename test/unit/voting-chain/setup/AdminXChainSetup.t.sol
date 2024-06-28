// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";

import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";

import {AdminXChainSetup, AdminXChain} from "@voting-chain/setup/AdminXChainSetup.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract TestAdminXChainSetup is TestHelpers {
    using ProxyLib for address;

    AdminXChainSetup setup;
    MockLzEndpointMinimal lzEndpoint;
    DAO dao;

    function setUp() public {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        setup = new AdminXChainSetup(new AdminXChain());

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO(address(this));
    }

    function testFuzz_initialState(address payable _admin) public {
        setup = new AdminXChainSetup(AdminXChain(_admin));

        assertEq(setup.implementation(), _admin);
    }

    // prepare installation
    function test_prepareInstallation() public {
        bytes memory data = abi.encode(address(lzEndpoint));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // check the contracts are deployed
        AdminXChain admin = AdminXChain(payable(plugin));
        assertEq(
            admin.OAPP_ADMINISTRATOR_ID(),
            keccak256("OAPP_ADMINISTRATOR"),
            "AdminXChain should have the correct OAPP_ADMINISTRATOR_ID"
        );

        // apply permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        // dao == oapp on admin
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(admin),
                _permissionId: admin.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the plugin"
        );

        // plugin == execute on dao
        assertTrue(
            dao.hasPermission({
                _who: address(admin),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "Plugin should have execute permission on the dao"
        );

        // dao == sweep on plugin
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(admin),
                _permissionId: admin.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            "DAO should have sweep permission on the plugin"
        );
    }

    function test_prepareUninstallation() public {
        bytes memory data = abi.encode(address(lzEndpoint));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        AdminXChain admin = AdminXChain(payable(plugin));

        // apply permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: plugin,
            currentHelpers: preparedData.helpers,
            data: data
        });

        PermissionLib.MultiTargetPermission[] memory permissions = setup.prepareUninstallation(
            address(dao),
            payload
        );

        dao.applyMultiTargetPermissions(permissions);

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(admin),
                _permissionId: admin.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should not be oapp admin of the plugin"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(admin),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "Plugin should not have execute permission on the dao"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(admin),
                _permissionId: admin.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            "DAO should not have sweep permission on the plugin"
        );
    }
}
