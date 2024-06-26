// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup, PermissionLib} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
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
import {TokenVotingSetup, TokenVoting, GovernanceERC20, GovernanceWrappedERC20, ITokenVoting} from "@aragon/token-voting/TokenVotingSetup.sol";
import {AdminSetup, Admin} from "@aragon/admin/AdminSetup.sol";

import "@utils/converters.sol";
import "@helpers/OSxHelpers.sol";

contract MockVotingPlugin {
    bytes4 _iface;
    ITokenVoting.VotingMode _votingMode;

    function setIface(bytes4 iface) public {
        _iface = iface;
    }

    function supportsInterface(bytes4 _interfaceId) external view returns (bool) {
        return _interfaceId == _iface;
    }

    function votingMode() public view returns (ITokenVoting.VotingMode) {
        return _votingMode;
    }

    function setVotingMode(ITokenVoting.VotingMode _mode) public {
        _votingMode = _mode;
    }
}

contract TestToucanReceiverSetup is TestHelpers {
    GovernanceOFTAdapter adapter;
    ActionRelay relay;
    ToucanReceiverSetup setup;
    MockLzEndpointMinimal lzEndpoint;
    DAO dao;
    ToucanReceiver receiver;

    function setUp() public {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        setup = new ToucanReceiverSetup(new GovernanceOFTAdapter(), new ActionRelay());
    }

    function testFuzz_constructor(address _adapter, address _actionRelay) public {
        setup = new ToucanReceiverSetup(GovernanceOFTAdapter(_adapter), ActionRelay(_actionRelay));
        assertEq(setup.oftAdapterBase(), _adapter);
        assertEq(setup.actionRelayBase(), _actionRelay);
    }

    // test validate voting plugin: must support iface and be in vote replacement mode
    function testFuzz_validateVotingPluginSupportsInterface(address _plugin, bytes4 _iface) public {
        vm.assume(_iface != setup.TOKEN_VOTING_INTERFACE_ID());

        MockVotingPlugin plugin = new MockVotingPlugin();

        // empty address will just revert
        // wrong inteface
        // right interface
    }

    // invalid plugin reverts prepinstallation

    // prepare installation
    // -deploys plugin, adapter and relay
    // -sets up permissions correctly
    // -sets helpers correctly

    // prepare uninstallation
    // wrong helpers length doesn't work
    // -removes permissions correctly
}
