// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";

import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";

import {ToucanRelaySetup, ToucanRelay, GovernanceERC20VotingChain} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {MockVotingPluginValidator as MockVotingPlugin} from "@mocks/MockToucanVoting.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract TestToucanRelaySetup is TestHelpers {
    using ProxyLib for address;

    ToucanRelaySetup setup;
    MockLzEndpointMinimal lzEndpoint;
    DAO dao;

    function setUp() public {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        setup = new ToucanRelaySetup(
            new ToucanRelay(),
            new OFTTokenBridge(),
            new GovernanceERC20VotingChain(IDAO(address(dao)), "name", "SYMBOL")
        );

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO(address(this));
    }

    function testFuzz_initialState(address _relay, address _bridge, address _votingToken) public {
        setup = new ToucanRelaySetup(
            ToucanRelay(_relay),
            OFTTokenBridge(_bridge),
            GovernanceERC20VotingChain(_votingToken)
        );

        assertEq(setup.relayBase(), _relay);
        assertEq(setup.bridgeBase(), _bridge);
        assertEq(setup.votingTokenBase(), _votingToken);
        assertEq(setup.implementation(), _relay);
    }

    // // test validate voting plugin: must support iface and be in vote replacement mode
    // function testFuzz_validateVotingPluginSupportsInterface(bytes4 _iface) public {
    //     vm.assume(_iface != setup.TOKEN_VOTING_INTERFACE_ID());

    //     MockVotingPlugin plugin;

    //     // empty address will just revert
    //     vm.expectRevert();
    //     setup.validateVotingPlugin(address(plugin));

    //     plugin = new MockVotingPlugin();

    //     // wrong inteface right voting mode
    //     plugin.setVotingMode(ITokenVoting.VotingMode.VoteReplacement);
    //     plugin.setIface(_iface);
    //     bytes memory revertData = abi.encodeWithSelector(
    //         ToucanRelaySetup.InvalidInterface.selector
    //     );
    //     vm.expectRevert(revertData);
    //     setup.validateVotingPlugin(address(plugin));

    //     // right interface
    //     plugin.setIface(tokenVotingIface());

    //     assertEq(address(setup.validateVotingPlugin(address(plugin))), address(plugin));
    // }

    // function test_validatePluginMustBeInVoteReplacementMode() public {
    //     MockVotingPlugin plugin = new MockVotingPlugin();
    //     plugin.setIface(tokenVotingIface());
    //     plugin.setVotingMode(ITokenVoting.VotingMode.Standard);

    //     bytes memory revertData = abi.encodeWithSelector(
    //         ToucanRelaySetup.NotInVoteReplacementMode.selector
    //     );
    //     vm.expectRevert(revertData);
    //     setup.validateVotingPlugin(address(plugin));

    //     plugin.setVotingMode(ITokenVoting.VotingMode.EarlyExecution);
    //     vm.expectRevert(revertData);
    //     setup.validateVotingPlugin(address(plugin));

    //     plugin.setVotingMode(ITokenVoting.VotingMode.VoteReplacement);
    //     assertEq(address(setup.validateVotingPlugin(address(plugin))), address(plugin));
    // }

    // // invalid plugin reverts prepinstallation
    // function test_invalidPluginRevertsInstallation() public {
    //     bytes memory data = abi.encode(address(0), address(1));
    //     vm.expectRevert();
    //     setup.prepareInstallation(address(0), data);

    //     MockVotingPlugin plugin = new MockVotingPlugin();
    //     data = abi.encode(address(plugin), address(plugin));
    //     vm.expectRevert(abi.encodeWithSelector(ToucanRelaySetup.InvalidInterface.selector));
    //     setup.prepareInstallation(address(0), data);
    // }

    // // prepare installation
    // function test_prepareInstallation() public {
    //     GovernanceERC20 token = deployToken();
    //     TokenVoting voting = deployTokenVoting(dao, address(token));

    //     bytes memory data = abi.encode(address(lzEndpoint), address(voting));

    //     (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
    //         .prepareInstallation(address(dao), data);

    //     // check the contracts are deployed
    //     ToucanRelay receiver = ToucanRelay(payable(plugin));
    //     assertEq(address(receiver.votingPlugin()), address(voting));

    //     OFTTokenBridge adapter = OFTTokenBridge(preparedData.helpers[0]);
    //     assertEq(address(adapter.token()), address(token));

    //     ActionRelay actionRelay = ActionRelay(preparedData.helpers[1]);
    //     assertEq(actionRelay.XCHAIN_ACTION_RELAYER_ID(), keccak256("XCHAIN_ACTION_RELAYER"));

    //     // apply permissions
    //     dao.applyMultiTargetPermissions(preparedData.permissions);

    //     // token voting should be in vote replacement mode
    //     ITokenVoting.VotingMode votingMode = voting.votingMode();
    //     assertEq(
    //         uint8(votingMode),
    //         uint8(ITokenVoting.VotingMode.VoteReplacement),
    //         "voting mode should be vote replacement"
    //     );

    //     // dao should have XChain execute on xchain relay
    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.XCHAIN_ACTION_RELAYER_ID(),
    //             _data: ""
    //         }),
    //         "DAO should have XChain execute on xchain relay"
    //     );

    //     // dao should be sweeper on the receiver
    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.SWEEP_COLLECTOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to sweep refunds from adminXChain"
    //     );

    //     // dao should be oapp admin of the receiver, adapter and action relay
    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the receiver"
    //     );

    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(adapter),
    //             _permissionId: adapter.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the adapter"
    //     );

    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the action relay"
    //     );

    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the action relay"
    //     );

    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(adapter),
    //             _permissionId: adapter.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the adapter"
    //     );

    //     assertTrue(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the receiver"
    //     );

    //     // adapter should delegate to the receiver
    //     assertEq(
    //         token.delegates(address(adapter)),
    //         address(receiver),
    //         "adapter should delegate to the receiver"
    //     );

    //     // voting token should be shared across plugin, receiver and adapter
    //     assertEq(
    //         adapter.token(),
    //         address(token),
    //         "adapter should have the voting token as underlying"
    //     );

    //     assertEq(
    //         address(receiver.governanceToken()),
    //         address(token),
    //         "receiver should have the voting token as underlying"
    //     );

    //     assertEq(
    //         address(voting.getVotingToken()),
    //         address(token),
    //         "voting should have the voting token as underlying"
    //     );
    // }

    // function test_FuzzCorrectHelpers(IPluginSetup.SetupPayload memory payload) public {
    //     vm.assume(payload.currentHelpers.length != 2);

    //     vm.expectRevert(
    //         abi.encodeWithSelector(
    //             ToucanRelaySetup.WrongHelpersArrayLength.selector,
    //             payload.currentHelpers.length
    //         )
    //     );
    //     setup.prepareUninstallation(address(0), payload);
    // }

    // function test_prepareUninstallation() public {
    //     GovernanceERC20 token = deployToken();
    //     TokenVoting voting = deployTokenVoting(dao, address(token));
    //     bytes memory data = abi.encode(address(lzEndpoint), address(voting));
    //     (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
    //         .prepareInstallation(address(dao), data);

    //     ToucanRelay receiver = ToucanRelay(payable(plugin));
    //     OFTTokenBridge adapter = OFTTokenBridge(preparedData.helpers[0]);
    //     ActionRelay actionRelay = ActionRelay(preparedData.helpers[1]);

    //     // apply, prepare and then unapply
    //     dao.applyMultiTargetPermissions(preparedData.permissions);

    //     IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
    //         plugin: plugin,
    //         currentHelpers: preparedData.helpers,
    //         data: data
    //     });

    //     PermissionLib.MultiTargetPermission[] memory permissions = setup.prepareUninstallation(
    //         address(dao),
    //         payload
    //     );

    //     dao.applyMultiTargetPermissions(permissions);

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.XCHAIN_ACTION_RELAYER_ID(),
    //             _data: ""
    //         }),
    //         "DAO should have XChain execute on xchain relay"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.SWEEP_COLLECTOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to sweep refunds from adminXChain"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the receiver"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(adapter),
    //             _permissionId: adapter.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the adapter"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.OAPP_ADMINISTRATOR_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be oapp admin of the action relay"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(actionRelay),
    //             _permissionId: actionRelay.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the action relay"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(adapter),
    //             _permissionId: adapter.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the adapter"
    //     );

    //     assertFalse(
    //         dao.hasPermission({
    //             _who: address(dao),
    //             _where: address(receiver),
    //             _permissionId: receiver.UPGRADE_PLUGIN_PERMISSION_ID(),
    //             _data: ""
    //         }),
    //         "DAO should be able to upgrade the receiver"
    //     );
    // }
}
