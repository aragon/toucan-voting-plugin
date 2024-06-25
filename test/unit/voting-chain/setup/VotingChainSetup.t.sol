// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";

import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";

import {ToucanRelaySetup} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";

import "@utils/converters.sol";

contract TestVotingChainOSx is TestHelpers {
    address trustedDeployer = address(0xc0ffeeb00b5);

    function testIt() public {
        vm.label(trustedDeployer, "trustedDeployer");

        // deploy the mock PSP with the admin plugin
        AdminSetup adminSetup = new AdminSetup();
        MockPluginSetupProcessor mockPSP = new MockPluginSetupProcessor(address(adminSetup));
        MockDAOFactory mockDAOFactory = new MockDAOFactory(mockPSP);
        MockLzEndpointMinimal lzEndpoint = new MockLzEndpointMinimal();

        bytes memory data = abi.encode(trustedDeployer);

        // use the OSx DAO factory with the Admin Plugin
        DAO dao = mockDAOFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the admin contract behind the proxy
        Admin admin = Admin(computeAddress(address(adminSetup), 2));
        assertEq(admin.isMember(trustedDeployer), true, "trustedDeployer should be a member");

        // setup the voting chain: we need 2 setup contracts for the toucanRelay and the adminXChain
        ToucanRelaySetup toucanRelaySetup = new ToucanRelaySetup(
            new OFTTokenBridge(),
            new GovernanceERC20VotingChain(IDAO(address(dao)), "TestToken", "TT")
        );

        // set it on the mock psp
        mockPSP.setSetup(address(toucanRelaySetup));

        // prepare the installation
        data = abi.encode(
            ToucanRelaySetup.InstallationParams({
                lzEndpoint: address(lzEndpoint),
                token: address(0),
                bridge: address(0),
                name: "vTestToken",
                symbol: "vTT"
            })
        );
        (address toucanRelay, IPluginSetup.PreparedSetupData memory toucanRelaySetupData) = mockPSP
            .prepareInstallation(address(dao), _mockPrepareInstallationParams(data));

        // apply the installation
        vm.startPrank(trustedDeployer);
        {
            IDAO.Action[] memory actions = new IDAO.Action[](3);
            actions[0] = IDAO.Action({
                to: address(dao),
                value: 0,
                data: abi.encodeCall(
                    dao.grant,
                    (address(dao), address(mockPSP), dao.ROOT_PERMISSION_ID())
                )
            });

            actions[1] = IDAO.Action({
                to: address(mockPSP),
                value: 0,
                data: abi.encodeCall(
                    mockPSP.applyInstallation,
                    (address(dao), _mockApplyInstallationParams(toucanRelay, toucanRelaySetupData))
                )
            });

            actions[2] = IDAO.Action({
                to: address(dao),
                value: 0,
                data: abi.encodeCall(
                    dao.revoke,
                    (address(dao), address(mockPSP), dao.ROOT_PERMISSION_ID())
                )
            });

            admin.executeProposal({_metadata: "", _actions: actions, _allowFailureMap: 0});
        }
        vm.stopPrank();
    }

    // eth address derivation using RLP encoding
    // use this if you can't get the address directly and don't have access to CREATE2
    function computeAddress(address target, uint8 nonce) internal pure returns (address) {
        bytes memory data;
        if (nonce == 0) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), target, bytes1(0x80));
        } else if (nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), target, uint8(nonce));
        } else if (nonce <= 0xff) {
            data = abi.encodePacked(bytes1(0xd7), bytes1(0x94), target, bytes1(0x81), uint8(nonce));
        } else if (nonce <= 0xffff) {
            data = abi.encodePacked(
                bytes1(0xd8),
                bytes1(0x94),
                target,
                bytes1(0x82),
                uint16(nonce)
            );
        } else if (nonce <= 0xffffff) {
            data = abi.encodePacked(
                bytes1(0xd9),
                bytes1(0x94),
                target,
                bytes1(0x83),
                uint24(nonce)
            );
        } else {
            data = abi.encodePacked(
                bytes1(0xda),
                bytes1(0x94),
                target,
                bytes1(0x84),
                uint32(nonce)
            );
        }

        return bytes32ToAddress(keccak256(data));
    }

    function _mockDAOSettings() internal pure returns (MockDAOFactory.DAOSettings memory) {
        return
            MockDAOFactory.DAOSettings({
                trustedForwarder: address(0),
                daoURI: "test",
                subdomain: "test",
                metadata: new bytes(0)
            });
    }

    // all this data is unused in the mock
    function _mockPluginSetupRef() internal pure returns (PluginSetupRef memory) {
        return
            PluginSetupRef({
                pluginSetupRepo: PluginRepo(address(0)),
                versionTag: PluginRepo.Tag({release: 1, build: 0})
            });
    }

    function _mockPrepareInstallationParams(
        bytes memory data
    ) internal pure returns (MockPluginSetupProcessor.PrepareInstallationParams memory) {
        return MockPluginSetupProcessor.PrepareInstallationParams(_mockPluginSetupRef(), data);
    }

    function _mockApplyInstallationParams(
        address plugin,
        IPluginSetup.PreparedSetupData memory preparedSetupData
    ) internal pure returns (MockPluginSetupProcessor.ApplyInstallationParams memory) {
        return
            MockPluginSetupProcessor.ApplyInstallationParams(
                _mockPluginSetupRef(),
                plugin,
                preparedSetupData.permissions,
                bytes32("helpersHash")
            );
    }

    /// we don't use most of the plugin settings in the mock so just ignore it
    function _mockPluginSettings(
        bytes memory data
    ) internal pure returns (MockDAOFactory.PluginSettings[] memory) {
        MockDAOFactory.PluginSettings[] memory settings = new MockDAOFactory.PluginSettings[](1);
        settings[0] = MockDAOFactory.PluginSettings({
            pluginSetupRef: _mockPluginSetupRef(),
            data: data
        });
        return settings;
    }
}
