// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {deployMockToucanVoting} from "@utils/deployers.sol";
import {ToucanVotingTestBase} from "./ToucanVotingBase.t.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {_applyRatioCeiled, RatioOutOfBounds, RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";

contract TestToucanVotingSettings is ToucanVotingTestBase {
    event MembershipContractAnnounced(address indexed definingContract);
    event VotingSettingsUpdated(
        IToucanVoting.VotingMode votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_cannotUpdateWithoutPermission(address _who) public {
        vm.assume(_who != address(this));
        bytes memory revertData = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            IDAO(address(dao)),
            address(voting),
            _who,
            voting.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        );
        vm.expectRevert(revertData);
        vm.prank(_who);
        voting.updateVotingSettings(_votingSettings(0, 0, 0, 0, 0));
    }

    function testFuzz_supportThresholdOOB(VotingSettingTest memory _settings) public {
        vm.assume(_settings.supportThreshold > RATIO_BASE - 1);
        IToucanVoting.VotingSettings memory settings = _convertTestSettings(_settings);
        bytes memory revertData = abi.encodeWithSelector(
            RatioOutOfBounds.selector,
            RATIO_BASE - 1,
            settings.supportThreshold
        );
        vm.expectRevert(revertData);
        voting.updateVotingSettings(settings);
    }

    function testFuzz_minParticipationOOB(VotingSettingTest memory _settings) public {
        vm.assume(_settings.minParticipation > RATIO_BASE);
        IToucanVoting.VotingSettings memory settings = _convertTestSettings(_settings);
        settings.supportThreshold = 0;

        bytes memory revertData = abi.encodeWithSelector(
            RatioOutOfBounds.selector,
            RATIO_BASE,
            settings.minParticipation
        );

        vm.expectRevert(revertData);
        voting.updateVotingSettings(settings);
    }

    function testFuzz_minDurationOOBLow(VotingSettingTest memory _settings) public {
        vm.assume(_settings.minDuration < 60 minutes);
        IToucanVoting.VotingSettings memory settings = _convertTestSettings(_settings);
        settings.supportThreshold = 0;
        settings.minParticipation = 0;

        bytes memory revertData = abi.encodeWithSelector(
            ToucanVoting.MinDurationOutOfBounds.selector,
            60 minutes,
            settings.minDuration
        );

        vm.expectRevert(revertData);
        voting.updateVotingSettings(settings);
    }

    function testFuzz_minDurationOOBHigh(VotingSettingTest memory _settings) public {
        vm.assume(_settings.minDuration > 365 days);
        IToucanVoting.VotingSettings memory settings = _convertTestSettings(_settings);
        settings.supportThreshold = 0;
        settings.minParticipation = 0;

        bytes memory revertData = abi.encodeWithSelector(
            ToucanVoting.MinDurationOutOfBounds.selector,
            365 days,
            settings.minDuration
        );

        vm.expectRevert(revertData);
        voting.updateVotingSettings(settings);
    }

    function testFuzz_updatesSettings(VotingSettingTest memory _settings) public {
        IToucanVoting.VotingSettings memory settings = _convertTestSettings(_settings);
        settings = _validVotingSettings(settings);

        vm.expectEmit(false, false, false, true);
        emit VotingSettingsUpdated(
            settings.votingMode,
            settings.supportThreshold,
            settings.minParticipation,
            settings.minDuration,
            settings.minProposerVotingPower
        );
        voting.updateVotingSettings(settings);

        assertEq(voting.supportThreshold(), settings.supportThreshold);
        assertEq(voting.minParticipation(), settings.minParticipation);
        assertEq(voting.minDuration(), settings.minDuration);
        assertEq(voting.minProposerVotingPower(), settings.minProposerVotingPower);
        assertEq(uint8(voting.votingMode()), uint8(settings.votingMode));
    }
}
