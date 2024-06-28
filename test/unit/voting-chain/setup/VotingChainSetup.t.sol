// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";

import {ToucanRelaySetup, ToucanRelay} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {AdminXChainSetup, AdminXChain} from "@voting-chain/setup/AdminXChainSetup.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract TestVotingChainOSx is TestHelpers {
    address trustedDeployer = address(0x420420420);

    // osx contracts
    MockPluginSetupProcessor mockPSP;
    MockDAOFactory mockDAOFactory;

    // layer zero
    MockLzEndpointMinimal lzEndpoint;
    uint32 remoteEid = 123;
    address remoteActionRelay = address(1);
    address remoteReceiver = address(2);
    address remoteAdapter = address(3);

    // dao
    DAO dao;

    // plugin setups
    AdminSetup adminSetup;
    ToucanRelaySetup toucanRelaySetup;
    AdminXChainSetup adminXChainSetup;

    // plugins
    GovernanceERC20VotingChain token;
    OFTTokenBridge bridge;
    Admin admin;
    ToucanRelay toucanRelay;
    AdminXChain adminXChain;

    // setup
    PermissionLib.MultiTargetPermission[] toucanRelayPermissions;
    PermissionLib.MultiTargetPermission[] adminXChainPermissions;
    PermissionLib.MultiTargetPermission[] adminUninstallPermissions;

    function testIt() public {
        _addLabels();
        _deployL0();
        _deployOSX();
        _deployDAOAndAdmin();
        _prepareSetupRelay();
        _prepareSetupAdminXChain();
        _prepareUninstallAdmin();

        // you would wait until the execution chain is deployed and the addresses of the
        // remote peers are known
        _applyInstallationsSetPeersRevokeAdmin();

        _validateEndState();
    }

    function _deployOSX() internal {
        // deploy the mock PSP with the admin plugin
        adminSetup = new AdminSetup();
        mockPSP = new MockPluginSetupProcessor(address(adminSetup));
        mockDAOFactory = new MockDAOFactory(mockPSP);
    }

    function _deployL0() internal {
        lzEndpoint = new MockLzEndpointMinimal();
    }

    function _deployDAOAndAdmin() internal {
        // use the OSx DAO factory with the Admin Plugin
        bytes memory data = abi.encode(trustedDeployer);
        dao = mockDAOFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the admin contract behind the proxy
        admin = Admin(computeAddress(address(adminSetup), 2));
        assertEq(admin.isMember(trustedDeployer), true, "trustedDeployer should be a member");

        vm.label(address(dao), "dao");
        vm.label(address(admin), "admin");
    }

    function _addLabels() internal {
        vm.label(trustedDeployer, "trustedDeployer");
    }

    function _prepareSetupRelay() internal {
        // setup the voting chain: we need 2 setup contracts for the toucanRelay and the adminXChain
        toucanRelaySetup = new ToucanRelaySetup(
            new ToucanRelay(),
            new OFTTokenBridge(),
            new GovernanceERC20VotingChain(IDAO(address(dao)), "TestToken", "TT")
        );

        // set it on the mock psp
        mockPSP.queueSetup(address(toucanRelaySetup));

        // prepare the installation
        bytes memory data = abi.encode(address(lzEndpoint), "vTestToken", "vTT");
        (
            address toucanRelayAddress,
            IPluginSetup.PreparedSetupData memory toucanRelaySetupData
        ) = mockPSP.prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < toucanRelaySetupData.permissions.length; i++) {
            toucanRelayPermissions.push(toucanRelaySetupData.permissions[i]);
        }

        toucanRelay = ToucanRelay(toucanRelayAddress);
        address[] memory helpers = toucanRelaySetupData.helpers;
        token = GovernanceERC20VotingChain(helpers[0]);
        bridge = OFTTokenBridge(helpers[1]);

        vm.label(toucanRelayAddress, "toucanRelay");
        vm.label(address(token), "token");
        vm.label(address(bridge), "bridge");
    }

    function _prepareSetupAdminXChain() internal {
        // setup the voting chain: we need 2 setup contracts for the toucanRelay and the adminXChain
        adminXChainSetup = new AdminXChainSetup(new AdminXChain());

        // set it on the mock psp
        mockPSP.queueSetup(address(adminXChainSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(lzEndpoint));
        (
            address adminXChainAddress,
            IPluginSetup.PreparedSetupData memory adminXChainSetupData
        ) = mockPSP.prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < adminXChainSetupData.permissions.length; i++) {
            adminXChainPermissions.push(adminXChainSetupData.permissions[i]);
        }

        adminXChain = AdminXChain(payable(adminXChainAddress));

        vm.label(adminXChainAddress, "adminXChain");
    }

    function _prepareUninstallAdmin() internal {
        // psp will use the admin setup in next call
        mockPSP.queueSetup(address(adminSetup));

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(admin),
            currentHelpers: new address[](0),
            data: new bytes(0)
        });

        // prepare the uninstallation
        PermissionLib.MultiTargetPermission[] memory permissions = mockPSP.prepareUninstallation(
            address(dao),
            _mockPrepareUninstallationParams(payload)
        );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < permissions.length; i++) {
            adminUninstallPermissions.push(permissions[i]);
        }
    }

    function _applyInstallationsSetPeersRevokeAdmin() internal {
        IDAO.Action[] memory actions = new IDAO.Action[](6);

        // action 0: apply the toucanRelay installation
        actions[0] = IDAO.Action({
            to: address(mockPSP),
            value: 0,
            data: abi.encodeCall(
                mockPSP.applyInstallation,
                (
                    address(dao),
                    _mockApplyInstallationParams(address(toucanRelay), toucanRelayPermissions)
                )
            )
        });

        // action 1: apply the adminXChain installation
        actions[1] = IDAO.Action({
            to: address(mockPSP),
            value: 0,
            data: abi.encodeCall(
                mockPSP.applyInstallation,
                (
                    address(dao),
                    _mockApplyInstallationParams(address(adminXChain), adminXChainPermissions)
                )
            )
        });

        // action 2,3,4: set the peers
        actions[2] = IDAO.Action({
            to: address(toucanRelay),
            value: 0,
            data: abi.encodeCall(toucanRelay.setPeer, (remoteEid, addressToBytes32(remoteReceiver)))
        });

        actions[3] = IDAO.Action({
            to: address(adminXChain),
            value: 0,
            data: abi.encodeCall(
                adminXChain.setPeer,
                (remoteEid, addressToBytes32(remoteActionRelay))
            )
        });

        actions[4] = IDAO.Action({
            to: address(bridge),
            value: 0,
            data: abi.encodeCall(adminXChain.setPeer, (remoteEid, addressToBytes32(remoteAdapter)))
        });

        // action 5: uninstall the admin plugin
        actions[5] = IDAO.Action({
            to: address(mockPSP),
            value: 0,
            data: abi.encodeCall(
                mockPSP.applyUninstallation,
                (
                    address(dao),
                    _mockApplyUninstallationParams(address(admin), adminUninstallPermissions)
                )
            )
        });

        // wrap the actions in grant/revoke root permissions
        IDAO.Action[] memory wrappedActions = wrapGrantRevokeRoot(dao, address(mockPSP), actions);

        // execute the actions
        vm.startPrank(trustedDeployer);
        {
            admin.executeProposal({_metadata: "", _actions: wrappedActions, _allowFailureMap: 0});
        }
        vm.stopPrank();
    }

    function _validateEndState() internal view {
        // check that the admin is uninstalled
        assertEq(
            dao.hasPermission({
                _who: address(admin),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            false,
            "admin should not have execute permission"
        );

        // check that xchain admin has execute on the dao
        assertEq(
            dao.hasPermission({
                _who: address(adminXChain),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            true,
            "xchain admin should have execute permission"
        );

        // check the DAO is the OAPP admin for the xchain contracts: relay, xchain and bridge
        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(toucanRelay),
                _permissionId: toucanRelay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be the OAPP admin for the toucanRelay"
        );

        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(adminXChain),
                _permissionId: adminXChain.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be the OAPP admin for the adminXChain"
        );

        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(bridge),
                _permissionId: bridge.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be the OAPP admin for the bridge"
        );

        // check that the peers are all set for the crosschain contracts
        assertEq(
            bytes32ToAddress(toucanRelay.peers(remoteEid)),
            remoteReceiver,
            "toucanRelay should have the remote receiver as a peer"
        );

        assertEq(
            bytes32ToAddress(adminXChain.peers(remoteEid)),
            remoteActionRelay,
            "adminXChain should have the remote action relay as a peer"
        );

        assertEq(
            bytes32ToAddress(bridge.peers(remoteEid)),
            remoteAdapter,
            "bridge should have the remote adapter as a peer"
        );

        // check that the token is deployed and the bridge has mint/burn ability
        assertEq(token.name(), "vTestToken", "token should be deployed with the correct name");
        assertEq(token.symbol(), "vTT", "token should be deployed with the correct symbol");

        assertEq(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.MINT_PERMISSION_ID(),
                _data: ""
            }),
            true,
            "bridge should have mint permission on the token"
        );

        assertEq(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.BURN_PERMISSION_ID(),
                _data: ""
            }),
            true,
            "bridge should have burn permission on the token"
        );

        // DAO should be able to sweep refunds from adminxchain
        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(adminXChain),
                _permissionId: adminXChain.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be able to sweep refunds from adminXChain"
        );
    }
}
