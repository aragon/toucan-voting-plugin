// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IGovernanceWrappedERC20} from "@toucan-voting/ERC20/governance/IGovernanceWrappedERC20.sol";

import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";
import {PluginRepo} from "@aragon/osx/framework/plugin/repo/PluginRepo.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockERC20, MockERC20Votes} from "@mocks/MockERC20.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";

import {ToucanVotingSetup, ToucanVoting, GovernanceERC20, GovernanceWrappedERC20, IToucanVoting} from "@toucan-voting/ToucanVotingSetup.sol";
import {MockVotingPluginValidator as MockVotingPlugin} from "@mocks/MockToucanVoting.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract TestToucanVotingSetup is TestHelpers {
    bytes32 public constant MINT_PERMISSION_ID = keccak256("MINT_PERMISSION");
    using ProxyLib for address;

    ToucanVotingSetup setup;
    DAO dao;

    function setUp() public {
        // reset timestamps and blocks
        // setup requires (block - 1) lookup so start from 1
        vm.warp(1);
        vm.roll(1);

        GovernanceERC20 token = deployToken();
        setup = new ToucanVotingSetup(
            new ToucanVoting(),
            token,
            new GovernanceWrappedERC20(IERC20Upgradeable(address(token)), "test", "test")
        );

        dao = createTestDAO(address(this));
    }

    function testFuzz_initialState(address _voting, address _govToken, address _wrapped) public {
        setup = new ToucanVotingSetup(
            ToucanVoting(_voting),
            GovernanceERC20(_govToken),
            GovernanceWrappedERC20(_wrapped)
        );

        assertEq(setup.governanceERC20Base(), _govToken);
        assertEq(setup.governanceWrappedERC20Base(), _wrapped);
        assertEq(setup.implementation(), _voting);
    }

    function test_isERC20(address _notToken) public {
        vm.assume(_notToken > address(10)); // skip precompiles

        // oz erc20 should pass
        MockERC20 ozToken = new MockERC20();
        address govERC20Base = setup.governanceERC20Base();
        address govWrappedERC20Base = setup.governanceWrappedERC20Base();

        vm.assume(_notToken != address(ozToken));
        vm.assume(_notToken != govERC20Base);
        vm.assume(_notToken != govWrappedERC20Base);

        assertTrue(setup.isERC20(address(ozToken)), "oz erc20 should pass");
        assertTrue(setup.isERC20(address(govERC20Base)), "gov erc20 should pass");
        assertTrue(setup.isERC20(address(govWrappedERC20Base)), "wrapped gov erc20 should pass");

        // the above 3 should be the only 3 tokens in the system at the moment
        assertFalse(setup.isERC20(_notToken), "not erc20 should fail");
    }

    function test_isGovERC20(address _notGov) public {
        vm.assume(_notGov > address(10)); // skip precompiles

        address govERC20Base = setup.governanceERC20Base();
        address govWrappedERC20Base = setup.governanceWrappedERC20Base();

        assertTrue(setup.isGovernanceToken(govERC20Base), "gov erc20 should pass");
        assertTrue(setup.isGovernanceToken(govWrappedERC20Base), "wrapped gov erc20 should pass");

        // a basic OZ/IVotes passes
        MockERC20Votes ozVotes = new MockERC20Votes();
        assertTrue(setup.isGovernanceToken(address(ozVotes)), "oz votes should pass");

        // minimal custom votes passes
        MockMinimalCustomVotes customVotes = new MockMinimalCustomVotes();
        assertTrue(setup.isGovernanceToken(address(customVotes)), "custom votes should pass");

        // vanilla ERC20 fails
        MockERC20 ozToken = new MockERC20();
        assertFalse(setup.isGovernanceToken(address(ozToken)), "oz erc20 should fail");

        // everything else fails
        vm.assume(_notGov != address(ozVotes));
        vm.assume(_notGov != govERC20Base);
        vm.assume(_notGov != govWrappedERC20Base);
        vm.assume(_notGov != address(customVotes));

        assertFalse(setup.isGovernanceToken(_notGov), "not gov erc20 should fail");
    }

    function testFuzz_revertsInstallIfTokenNotContract(address _addr) public {
        vm.assume(_addr != address(0)); // zero indicates that we want to deploy the token
        vm.assume(_addr.code.length == 0);

        bytes memory data = baseSetupData(_addr);

        vm.expectRevert(abi.encodeWithSelector(ToucanVotingSetup.TokenNotContract.selector, _addr));
        setup.prepareInstallation(address(dao), data);
    }

    function testFuzz_revertsInstallIfNotERC20(bytes memory _noise) public {
        vm.assume(_noise.length != 0);

        // scribble some nonsense into the address
        address _addr = address(0x1234);
        vm.etch(_addr, _noise);

        bytes memory data = baseSetupData(_addr);

        vm.expectRevert(abi.encodeWithSelector(ToucanVotingSetup.TokenNotERC20.selector, _addr));
        setup.prepareInstallation(address(dao), data);
    }

    function test_FuzzCorrectHelpers(IPluginSetup.SetupPayload memory payload) public {
        vm.assume(payload.currentHelpers.length != 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToucanVotingSetup.WrongHelpersArrayLength.selector,
                payload.currentHelpers.length
            )
        );
        setup.prepareUninstallation(address(0), payload);
    }

    function test_prepareInstallationDeployToken() public {
        bytes memory data = baseSetupData(address(0));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // check the contracts are deployed
        GovernanceERC20 token = GovernanceERC20(preparedData.helpers[0]);
        assertEq(
            token.supportsInterface(type(IVotesUpgradeable).interfaceId),
            true,
            "Token should support IVotes"
        );

        // check it's not wrapped
        (bool success, ) = address(token).call(abi.encodeWithSignature("underlying()"));
        assertFalse(success, "Token should not be wrapped");

        ToucanVoting voting = ToucanVoting(plugin);
        assertEq(address(voting.getVotingToken()), address(token));

        // check the permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        checkPermissions(voting, address(token), true);
    }

    function test_prepareInstallationValidToken() public {
        MockERC20Votes token = new MockERC20Votes();
        bytes memory data = baseSetupData(address(token));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // check the helper matches
        assertEq(preparedData.helpers[0], address(token));

        // check it's not wrapped
        (bool success, ) = address(token).call(abi.encodeWithSignature("underlying()"));
        assertFalse(success, "Token should not be wrapped");

        ToucanVoting voting = ToucanVoting(plugin);
        assertEq(address(voting.getVotingToken()), address(token));

        // check the permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        checkPermissions(voting, address(token), false);
    }

    function test_prepareInstallationWrappedToken() public {
        MockERC20 token = new MockERC20();
        bytes memory data = baseSetupData(address(token));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // check we deployed a wrapped token
        GovernanceWrappedERC20 wrappedToken = GovernanceWrappedERC20(preparedData.helpers[0]);
        assertNotEq(address(wrappedToken), address(token), "Token should be wrapped");
        assertEq(address(wrappedToken.underlying()), address(token), "Underlying wrong");
        assertEq(
            wrappedToken.supportsInterface(type(IGovernanceWrappedERC20).interfaceId),
            true,
            "Wrapped token should support IVotes"
        );

        ToucanVoting voting = ToucanVoting(plugin);
        assertEq(address(voting.getVotingToken()), address(wrappedToken), "Voting token wrong");

        // check the permissions
        dao.applyMultiTargetPermissions(preparedData.permissions);

        checkPermissions(voting, address(wrappedToken), false);
    }

    function test_prepareUninstallation() public {
        bytes memory data = baseSetupData(address(0));

        (address plugin, IPluginSetup.PreparedSetupData memory preparedData) = setup
            .prepareInstallation(address(dao), data);

        // deploy and set permissions
        GovernanceERC20 token = GovernanceERC20(preparedData.helpers[0]);
        ToucanVoting voting = ToucanVoting(plugin);
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
                _where: address(voting),
                _permissionId: voting.UPDATE_VOTING_SETTINGS_PERMISSION_ID(),
                _data: ""
            }),
            "DAO should not have permission to update voting settings"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(voting),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "Voting should not have permission to execute on the DAO"
        );

        assertFalse(
            dao.hasPermission({
                _who: address(dao),
                _where: address(voting),
                _permissionId: voting.UPGRADE_PLUGIN_PERMISSION_ID(),
                _data: ""
            }),
            "DAO should not have permission to upgrade voting"
        );

        // this should not be revoked
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(token),
                _permissionId: MINT_PERMISSION_ID,
                _data: ""
            }),
            "Token should still have permission to mint"
        );
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

    function baseSetupData(address _token) public view returns (bytes memory) {
        // prep the data
        IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
            votingMode: IToucanVoting.VotingMode.VoteReplacement,
            supportThreshold: 1e5,
            minParticipation: 1e5,
            minDuration: 1 days,
            minProposerVotingPower: 1 ether
        });

        ToucanVotingSetup.TokenSettings memory tokenSettings = ToucanVotingSetup.TokenSettings({
            addr: _token,
            symbol: "TT",
            name: "TestToken"
        });

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](1),
            amounts: new uint256[](1)
        });
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 1_000_000_000 ether;

        bytes memory data = abi.encode(votingSettings, tokenSettings, mintSettings, false);
        return data;
    }

    function checkPermissions(ToucanVoting voting, address token, bool deployed) public view {
        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(voting),
                _permissionId: voting.UPDATE_VOTING_SETTINGS_PERMISSION_ID(),
                _data: ""
            }),
            "DAO should have permission to update voting settings"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(voting),
                _where: address(dao),
                _permissionId: dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "Voting should have permission to execute on the DAO"
        );

        assertTrue(
            dao.hasPermission({
                _who: address(dao),
                _where: address(voting),
                _permissionId: voting.UPGRADE_PLUGIN_PERMISSION_ID(),
                _data: ""
            }),
            "DAO should have permission to upgrade voting"
        );

        if (deployed) {
            assertTrue(
                dao.hasPermission({
                    _who: address(dao),
                    _where: token,
                    _permissionId: MINT_PERMISSION_ID,
                    _data: ""
                }),
                "Token should have permission to mint"
            );
        } else {
            assertFalse(
                dao.hasPermission({
                    _who: address(dao),
                    _where: token,
                    _permissionId: MINT_PERMISSION_ID,
                    _data: ""
                }),
                "Token should not have permission to mint"
            );
        }
    }
}

contract MockMinimalCustomVotes {
    function getVotes(address ) public pure returns (uint256) {
        return 0;
    }

    function getPastTotalSupply(uint256 ) public pure returns (uint256) {
        return 0;
    }

    function getPastVotes(address , uint256 ) public pure returns (uint256) {
        return 0;
    }
}
