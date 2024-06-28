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

import {ToucanReceiverSetup, ToucanReceiver, ActionRelay} from "@execution-chain/setup/ToucanReceiverSetup.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanVotingSetup, ToucanVoting, GovernanceERC20, GovernanceWrappedERC20, IToucanVoting} from "@toucan-voting/ToucanVotingSetup.sol";
import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {MockVotingPluginValidator as MockVotingPlugin} from "@mocks/MockToucanVoting.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract TestToucanReceiverSetup is TestHelpers {
    using ProxyLib for address;

    ToucanReceiverSetup setup;
    MockLzEndpointMinimal lzEndpoint;
    DAO dao;

    function setUp() public {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        setup = new ToucanReceiverSetup(
            new ToucanReceiver(),
            new GovernanceOFTAdapter(),
            new ActionRelay()
        );

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO(address(this));
    }

    function testFuzz_initialState(
        address payable _receiver,
        address _adapter,
        address _actionRelay
    ) public {
        setup = new ToucanReceiverSetup(
            ToucanReceiver(_receiver),
            GovernanceOFTAdapter(_adapter),
            ActionRelay(_actionRelay)
        );

        assertEq(setup.toucanReceiverBase(), _receiver);
        assertEq(setup.oftAdapterBase(), _adapter);
        assertEq(setup.actionRelayBase(), _actionRelay);

        assertEq(setup.implementation(), _receiver);
    }

    // test validate voting plugin: must support iface and be in vote replacement mode
    function testFuzz_validateVotingPluginSupportsInterface(bytes4 _iface) public {
        vm.assume(_iface != setup.TOKEN_VOTING_INTERFACE_ID());

        MockVotingPlugin plugin;

        // empty address will just revert
        vm.expectRevert();
        setup.validateVotingPlugin(address(plugin));

        plugin = new MockVotingPlugin();

        // wrong inteface right voting mode
        plugin.setVotingMode(IToucanVoting.VotingMode.VoteReplacement);
        plugin.setIface(_iface);
        bytes memory revertData = abi.encodeWithSelector(
            ToucanReceiverSetup.InvalidInterface.selector
        );
        vm.expectRevert(revertData);
        setup.validateVotingPlugin(address(plugin));

        // right interface
        plugin.setIface(tokenVotingIface());

        assertEq(address(setup.validateVotingPlugin(address(plugin))), address(plugin));
    }

    function test_validatePluginMustBeInVoteReplacementMode() public {
        MockVotingPlugin plugin = new MockVotingPlugin();
        plugin.setIface(tokenVotingIface());
        plugin.setVotingMode(IToucanVoting.VotingMode.Standard);

        bytes memory revertData = abi.encodeWithSelector(
            ToucanReceiverSetup.NotInVoteReplacementMode.selector
        );
        vm.expectRevert(revertData);
        setup.validateVotingPlugin(address(plugin));

        plugin.setVotingMode(IToucanVoting.VotingMode.EarlyExecution);
        vm.expectRevert(revertData);
        setup.validateVotingPlugin(address(plugin));

        plugin.setVotingMode(IToucanVoting.VotingMode.VoteReplacement);
        assertEq(address(setup.validateVotingPlugin(address(plugin))), address(plugin));
    }

    // invalid plugin reverts prepinstallation
    function test_invalidPluginRevertsInstallation() public {
        bytes memory data = abi.encode(address(0), address(1));
        vm.expectRevert();
        setup.prepareInstallation(address(0), data);

        MockVotingPlugin plugin = new MockVotingPlugin();
        data = abi.encode(address(plugin), address(plugin));
        vm.expectRevert(abi.encodeWithSelector(ToucanReceiverSetup.InvalidInterface.selector));
        setup.prepareInstallation(address(0), data);
    }

    // prepare installation
    function test_prepareInstallation() public {
        GovernanceERC20 token = deployToken();
        ToucanVoting voting = deployToucanVoting(dao, address(token));

        bytes memory data = abi.encode(address(lzEndpoint), address(voting));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // check the contracts are deployed
        ToucanReceiver receiver = ToucanReceiver(payable(plugin));
        assertEq(address(receiver.votingPlugin()), address(voting));

        GovernanceOFTAdapter adapter = GovernanceOFTAdapter(preparedData.helpers[0]);
        assertEq(address(adapter.token()), address(token));

        ActionRelay actionRelay = ActionRelay(preparedData.helpers[1]);
        assertEq(actionRelay.XCHAIN_ACTION_RELAYER_ID(), keccak256("XCHAIN_ACTION_RELAYER"));

        // apply permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        // token voting should be in vote replacement mode
        IToucanVoting.VotingMode votingMode = voting.votingMode();
        assertEq(
            uint8(votingMode),
            uint8(IToucanVoting.VotingMode.VoteReplacement),
            "voting mode should be vote replacement"
        );

        // dao should have XChain execute on xchain relay
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(actionRelay),
                _permissionId: actionRelay.XCHAIN_ACTION_RELAYER_ID(),
                _data: ""
            }),
            "DAO should have XChain execute on xchain relay"
        );

        // dao should be sweeper on the receiver
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            "DAO should be able to sweep refunds from adminXChain"
        );

        // dao should be oapp admin of the receiver, adapter and action relay
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the receiver"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(adapter),
                _permissionId: adapter.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the adapter"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(actionRelay),
                _permissionId: actionRelay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
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

    function test_FuzzCorrectHelpers(IPluginSetup.SetupPayload memory payload) public {
        vm.assume(payload.currentHelpers.length != 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToucanReceiverSetup.WrongHelpersArrayLength.selector,
                payload.currentHelpers.length
            )
        );
        setup.prepareUninstallation(address(0), payload);
    }

    function test_prepareUninstallation() public {
        GovernanceERC20 token = deployToken();
        ToucanVoting voting = deployToucanVoting(dao, address(token));
        bytes memory data = abi.encode(address(lzEndpoint), address(voting));
        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        ToucanReceiver receiver = ToucanReceiver(payable(plugin));
        GovernanceOFTAdapter adapter = GovernanceOFTAdapter(preparedData.helpers[0]);
        ActionRelay actionRelay = ActionRelay(preparedData.helpers[1]);

        // apply, prepare and then unapply
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
                _where: address(actionRelay),
                _permissionId: actionRelay.XCHAIN_ACTION_RELAYER_ID(),
                _data: ""
            }),
            "DAO should have XChain execute on xchain relay"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.SWEEP_COLLECTOR_ID(),
                _data: ""
            }),
            "DAO should be able to sweep refunds from adminXChain"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(receiver),
                _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the receiver"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(adapter),
                _permissionId: adapter.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the adapter"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(actionRelay),
                _permissionId: actionRelay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the action relay"
        );
    }

    function tokenVotingIface() public pure returns (bytes4) {
        return
            ToucanVoting.initialize.selector ^
            ToucanVoting.getVotingToken.selector ^
            ToucanVoting.minDuration.selector ^
            ToucanVoting.minProposerVotingPower.selector ^
            ToucanVoting.votingMode.selector ^
            ToucanVoting.totalVotingPower.selector ^
            ToucanVoting.getProposal.selector ^
            ToucanVoting.updateVotingSettings.selector ^
            ToucanVoting.createProposal.selector;
    }

    function deployToucanVoting(IDAO _dao, address _token) internal returns (ToucanVoting) {
        // prep the data
        IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
            votingMode: IToucanVoting.VotingMode.VoteReplacement,
            supportThreshold: 1e5,
            minParticipation: 1e5,
            minDuration: 1 days,
            minProposerVotingPower: 1 ether
        });
        // deploy the plugin
        ToucanVoting pluginBase = new ToucanVoting();

        // create a proxy
        address plugin = address(pluginBase).deployUUPSProxy(
            abi.encodeCall(
                ToucanVoting.initialize,
                (IDAO(_dao), votingSettings, IVotesUpgradeable(_token))
            )
        );

        return ToucanVoting(plugin);
    }

    function deployToken() internal returns (GovernanceERC20) {
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
        return baseToken;
    }
}
