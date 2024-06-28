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

import {ToucanRelaySetup, ToucanRelay, GovernanceERC20VotingChain} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
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

    function test_noEmptyStrings() public {
        vm.expectRevert(abi.encodeWithSelector(ToucanRelaySetup.InvalidTokenNameOrSymbol.selector));
        setup.prepareInstallation(address(0), abi.encode(address(lzEndpoint), "", "string"));

        vm.expectRevert(abi.encodeWithSelector(ToucanRelaySetup.InvalidTokenNameOrSymbol.selector));
        setup.prepareInstallation(address(0), abi.encode(address(lzEndpoint), "string", ""));

        vm.expectRevert(abi.encodeWithSelector(ToucanRelaySetup.InvalidTokenNameOrSymbol.selector));
        setup.prepareInstallation(address(0), abi.encode(address(lzEndpoint), "", ""));
    }

    // prepare installation
    function test_prepareInstallation() public {
        bytes memory data = abi.encode(address(lzEndpoint), "test", "TEST");

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        GovernanceERC20VotingChain token = GovernanceERC20VotingChain(preparedData.helpers[0]);
        assertEq(
            keccak256(abi.encode(token.CLOCK_MODE())),
            keccak256(abi.encode("mode=timestamp")),
            "Clock mode should be timestamp"
        );

        // check the contracts are deployed
        ToucanRelay relay = ToucanRelay(plugin);
        assertEq(address(relay.token()), address(token), "Token should be set on the relay");

        OFTTokenBridge bridge = OFTTokenBridge(preparedData.helpers[1]);
        assertEq(address(bridge.token()), address(token), "Token should be set on the adapter");

        // apply permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        assertTrue(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.MINT_PERMISSION_ID(),
                _data: ""
            }),
            "Bridge should have mint permission on the token"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.BURN_PERMISSION_ID(),
                _data: ""
            }),
            "Bridge should have burn permission on the token"
        );

        // dao should be oapp admin of the receiver, adapter and action relay
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(relay),
                _permissionId: relay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the receiver"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(bridge),
                _permissionId: bridge.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should be oapp admin of the bridge"
        );
    }

    function test_FuzzCorrectHelpers(IPluginSetup.SetupPayload memory payload) public {
        vm.assume(payload.currentHelpers.length != 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToucanRelaySetup.IncorrectHelpersLength.selector,
                2,
                payload.currentHelpers.length
            )
        );
        setup.prepareUninstallation(address(0), payload);
    }

    function test_prepareUninstallation() public {
        bytes memory data = abi.encode(address(lzEndpoint), "test", "TEST");

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        GovernanceERC20VotingChain token = GovernanceERC20VotingChain(preparedData.helpers[0]);
        ToucanRelay relay = ToucanRelay(plugin);
        OFTTokenBridge bridge = OFTTokenBridge(preparedData.helpers[1]);
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

        assertTrue(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.MINT_PERMISSION_ID(),
                _data: ""
            }),
            "Bridge should still have mint permission on the token"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(bridge),
                _where: address(token),
                _permissionId: token.BURN_PERMISSION_ID(),
                _data: ""
            }),
            "Bridge should still have burn permission on the token"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(relay),
                _permissionId: relay.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should not be oapp admin of the receiver"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(bridge),
                _permissionId: bridge.OAPP_ADMINISTRATOR_ID(),
                _data: ""
            }),
            "DAO should not be oapp admin of the bridge"
        );
    }
}
