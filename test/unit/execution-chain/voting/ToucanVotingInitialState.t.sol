// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {deployMockToucanVoting} from "@utils/deployers.sol";
import {ToucanVotingTestBase} from "./ToucanVotingBase.t.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";

contract TestToucanVotingInitialState is ToucanVotingTestBase {
    event MembershipContractAnnounced(address indexed definingContract);

    function setUp() public override {
        super.setUp();
    }

    function test_UUPSUpgrade() public {
        dao.grant({
            _who: address(this),
            _where: address(voting),
            _permissionId: voting.UPGRADE_PLUGIN_PERMISSION_ID()
        });
        MockUpgradeTo newImplementation = new MockUpgradeTo();
        voting.upgradeTo(address(newImplementation));

        assertEq(voting.implementation(), address(newImplementation));
        assertEq(MockUpgradeTo(address(voting)).v2Upgraded(), true);
    }

    function test_cannotReinitalize() public {
        ToucanVoting impl = new ToucanVoting();
        vm.expectRevert(initializableError);
        impl.initialize(IDAO(address(dao)), _votingSettings(0, 0, 0, 0, 0), address(token));
    }

    // TODO WTF
    // function testFuzz_initialState(
    //     IToucanVoting.VotingSettings memory _settings,
    //     address _token
    // ) public {
    //     // bound the settings
    //     _settings = _validVotingSettings(_settings);
    //     vm.etch(_token, address(token).code);

    //     vm.expectEmit(true, false, false, true);
    //     emit MembershipContractAnnounced(_token);
    //     ToucanVoting newToucan = deployMockToucanVoting(address(dao), _settings, _token);

    //     assertEq(address(newToucan.getVotingToken()), _token);
    // }

    function test_supportsIface() public view {
        assertTrue(voting.supportsInterface(voting.TOKEN_VOTING_INTERFACE_ID()));
        assertTrue(voting.supportsInterface(type(IMembership).interfaceId));
        assertTrue(voting.supportsInterface(type(IToucanVoting).interfaceId));
    }
}
