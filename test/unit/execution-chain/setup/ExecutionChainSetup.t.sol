// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";

import {ToucanReceiverSetup, ToucanReceiver, ActionRelay} from "@execution-chain/setup/ToucanReceiverSetup.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanVotingSetup, ToucanVoting, GovernanceERC20, GovernanceWrappedERC20, IToucanVoting} from "@toucan-voting/ToucanVotingSetup.sol";
import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

/// @dev On the execution chain we have 2 options:
/// 1. Fresh DAO, can use the admin plugin
/// 2. Existing DAO, must install via a proposal
/// These only bifurcate at the final execution step, where a proposal must be created.
contract TestExecutionChainOSx is TestHelpers {
    address trustedDeployer = address(0x420420420);
    address mintRecipient = address(0x696969696969);

    // osx contracts
    MockPluginSetupProcessor mockPSP;
    MockDAOFactory mockDAOFactory;

    // layer zero
    MockLzEndpointMinimal lzEndpoint;
    uint32 remoteEid = 123;
    address remoteXchainAdmin = address(1);
    address remoteRelay = address(2);
    address remoteBridge = address(3);

    // dao
    DAO dao;

    // plugin setups
    AdminSetup adminSetup;
    ToucanReceiverSetup receiverSetup;
    ToucanVotingSetup votingSetup;

    // plugins
    GovernanceERC20 token;
    GovernanceOFTAdapter adapter;
    Admin admin;
    ToucanReceiver receiver;
    ToucanVoting voting;
    ActionRelay actionRelay;

    // setup
    PermissionLib.MultiTargetPermission[] receiverPermissions;
    PermissionLib.MultiTargetPermission[] votingPermissions;
    PermissionLib.MultiTargetPermission[] adminUninstallPermissions;

    function testIt() public {
        _addLabels();
        _deployL0();
        _deployOSX();
        _deployDAOAndAdmin();
        _prepareSetupToucanVoting();
        _prepareSetupReceiver();
        _prepareUninstallAdmin();

        // you can do this immediately if you have already deployed the voting chain
        // if the dao already exists a proposal must be created
        // very similar workflow, but will require installing tokenVoting 2.0 and uninstalling tokenVoting 1.0
        // then creating the proposal
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

    function _prepareSetupToucanVoting() internal {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            new address[](1),
            new uint256[](1)
        );
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 0;

        GovernanceERC20 baseToken = new GovernanceERC20(
            IDAO(address(dao)),
            "Test Token",
            "TT",
            mintSettings
        );

        votingSetup = new ToucanVotingSetup(
            new ToucanVoting(),
            baseToken,
            new GovernanceWrappedERC20(
                IERC20Upgradeable(address(baseToken)),
                "Wrapped Test Token",
                "WTT"
            )
        );

        // push to the PSP
        mockPSP.queueSetup(address(votingSetup));

        // prep the data
        IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
            votingMode: IToucanVoting.VotingMode.VoteReplacement,
            supportThreshold: 1e5,
            minParticipation: 1e5,
            minDuration: 1 days,
            minProposerVotingPower: 1 ether
        });

        ToucanVotingSetup.TokenSettings memory tokenSettings = ToucanVotingSetup.TokenSettings({
            addr: address(0),
            symbol: "TT",
            name: "TestToken"
        });

        mintSettings.receivers[0] = mintRecipient;
        mintSettings.amounts[0] = 1_000_000_000 ether;

        bytes memory data = abi.encode(votingSettings, tokenSettings, mintSettings, false);

        (
            address votingPluginAddress,
            IPluginSetup.PreparedSetupData memory votingPluginPreparedSetupData
        ) = mockPSP.prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < votingPluginPreparedSetupData.permissions.length; i++) {
            votingPermissions.push(votingPluginPreparedSetupData.permissions[i]);
        }

        voting = ToucanVoting(votingPluginAddress);
        address[] memory helpers = votingPluginPreparedSetupData.helpers;
        token = GovernanceERC20(helpers[0]);

        vm.label(address(voting), "voting");
        vm.label(address(token), "token");
    }

    function _prepareSetupReceiver() internal {
        // deploy receiver and set it as next address for PSP to use
        receiverSetup = new ToucanReceiverSetup(
            new ToucanReceiver(),
            new GovernanceOFTAdapter(),
            new ActionRelay()
        );
        mockPSP.queueSetup(address(receiverSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(lzEndpoint), address(voting));

        (
            address receiverPluginAddress,
            IPluginSetup.PreparedSetupData memory receiverPluginPreparedSetupData
        ) = mockPSP.prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < receiverPluginPreparedSetupData.permissions.length; i++) {
            receiverPermissions.push(receiverPluginPreparedSetupData.permissions[i]);
        }

        receiver = ToucanReceiver(payable(receiverPluginAddress));
        address[] memory helpers = receiverPluginPreparedSetupData.helpers;
        adapter = GovernanceOFTAdapter(helpers[0]);
        actionRelay = ActionRelay(helpers[1]);

        vm.label(address(receiver), "receiver");
        vm.label(address(adapter), "adapter");
        vm.label(address(actionRelay), "actionRelay");
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

        // action 0: apply the tokenVoting installation
        actions[0] = IDAO.Action({
            to: address(mockPSP),
            value: 0,
            data: abi.encodeCall(
                mockPSP.applyInstallation,
                (address(dao), _mockApplyInstallationParams(address(voting), votingPermissions))
            )
        });

        // action 1: apply the receiver installation
        actions[1] = IDAO.Action({
            to: address(mockPSP),
            value: 0,
            data: abi.encodeCall(
                mockPSP.applyInstallation,
                (address(dao), _mockApplyInstallationParams(address(receiver), receiverPermissions))
            )
        });

        // action 2,3,4: set the peers
        actions[2] = IDAO.Action({
            to: address(receiver),
            value: 0,
            data: abi.encodeCall(receiver.setPeer, (remoteEid, addressToBytes32(remoteRelay)))
        });

        actions[3] = IDAO.Action({
            to: address(actionRelay),
            value: 0,
            data: abi.encodeCall(
                actionRelay.setPeer,
                (remoteEid, addressToBytes32(remoteXchainAdmin))
            )
        });

        actions[4] = IDAO.Action({
            to: address(adapter),
            value: 0,
            data: abi.encodeCall(adapter.setPeer, (remoteEid, addressToBytes32(remoteBridge)))
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
        // token voting should be in vote replacement mode
        IToucanVoting.VotingMode votingMode = voting.votingMode();
        assertEq(
            uint8(votingMode),
            uint8(IToucanVoting.VotingMode.VoteReplacement),
            "voting mode should be vote replacement"
        );

        // admin should be uninstalled
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

        // dao should have XChain execute on xchain relay
        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(actionRelay),
                _permissionId: actionRelay.XCHAIN_ACTION_RELAYER_ID(),
                _data: ""
            }),
            true,
            "DAO should have XChain execute on xchain relay"
        );

        // dao should be sweeper on the receiver
        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be able to sweep refunds from adminXChain"
        );

        // adapter should have the remote bridge as a peer
        assertEq(
            bytes32ToAddress(adapter.peers(remoteEid)),
            remoteBridge,
            "adapter should have the remote bridge as a peer"
        );

        // action relay should have the remote xchain admin as a peer
        assertEq(
            bytes32ToAddress(actionRelay.peers(remoteEid)),
            remoteXchainAdmin,
            "action relay should have the remote xchain admin as a peer"
        );

        // receiver should have the remote relay as a peer
        assertEq(
            bytes32ToAddress(receiver.peers(remoteEid)),
            remoteRelay,
            "receiver should have the remote relay as a peer"
        );

        // dao should be oapp admin of the receiver, adapter and action relay
        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be oapp admin of the receiver"
        );

        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(adapter),
                _permissionId: adapter.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be oapp admin of the adapter"
        );

        assertEq(
            dao.hasPermission({
                _who: address(dao),
                _where: address(actionRelay),
                _permissionId: actionRelay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            true,
            "DAO should be oapp admin of the action relay"
        );

        // adapter should delegate to the receiver
        assertEq(
            token.delegates(address(adapter)),
            address(receiver),
            "adapter should delegate to the receiver"
        );

        // voting token should be shared across plugin, receiver and adapter
        assertEq(
            adapter.token(),
            address(token),
            "adapter should have the voting token as underlying"
        );

        assertEq(
            address(receiver.governanceToken()),
            address(token),
            "receiver should have the voting token as underlying"
        );

        assertEq(
            address(voting.getVotingToken()),
            address(token),
            "voting should have the voting token as underlying"
        );
    }
}
