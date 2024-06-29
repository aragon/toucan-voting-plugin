// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {TestHelpers} from "@helpers/TestHelpers.sol";
import {deployMockToucanVoting} from "@utils/deployers.sol";
import {_applyRatioCeiled, RatioOutOfBounds, RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";

contract ToucanVotingTestBase is TestHelpers, IVoteContainer {
    GovernanceERC20 token;
    ToucanVoting voting;
    DAO dao;

    // constants
    uint8 public constant STANDARD_VOTING_MODE = 0;
    uint32 public constant SUPPORT_THRESHOLD = 0;
    uint32 public constant MIN_PARTICIPATION = 0;
    uint32 public constant MIN_DURATION = 3600;
    uint256 public constant MIN_PROPOSER_VOTING_POWER = 0;

    /// cant fuzz enums
    struct VotingSettingTest {
        uint8 votingMode;
        uint32 supportThreshold;
        uint32 minParticipation;
        uint32 minDuration;
        uint256 minProposerVotingPower;
    }

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        dao = createTestDAO(address(this));

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](0),
            amounts: new uint256[](0)
        });

        token = new GovernanceERC20(dao, "name", "SYMBOL", mintSettings);

        // this address can mint tokens
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });

        voting = deployMockToucanVoting(address(dao), _defaultVotingSettings(), address(token));

        // this address can update voting settings
        dao.grant({
            _who: address(this),
            _where: address(voting),
            _permissionId: voting.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });
    }

    function _votingSettings(
        uint8 _mode,
        uint32 _supportThreshold,
        uint32 _minParticipation,
        uint32 _minDuration,
        uint256 _minProposerVotingPower
    ) internal pure returns (IToucanVoting.VotingSettings memory) {
        return
            IToucanVoting.VotingSettings({
                votingMode: IToucanVoting.VotingMode(_mode),
                supportThreshold: _supportThreshold,
                minParticipation: _minParticipation,
                minDuration: _minDuration,
                minProposerVotingPower: _minProposerVotingPower
            });
    }

    function _defaultVotingSettings() internal pure returns (IToucanVoting.VotingSettings memory) {
        return
            _votingSettings(
                STANDARD_VOTING_MODE,
                SUPPORT_THRESHOLD,
                MIN_PARTICIPATION,
                MIN_DURATION,
                MIN_PROPOSER_VOTING_POWER
            );
    }

    function _convertTestSettings(
        VotingSettingTest memory _settings
    ) internal pure returns (IToucanVoting.VotingSettings memory) {
        return
            IToucanVoting.VotingSettings({
                votingMode: IToucanVoting.VotingMode(_settings.votingMode % 3),
                supportThreshold: _settings.supportThreshold,
                minParticipation: _settings.minParticipation,
                minDuration: _settings.minDuration,
                minProposerVotingPower: _settings.minProposerVotingPower
            });
    }

    function _validVotingSettings(
        IToucanVoting.VotingSettings memory _settings
    ) internal pure returns (IToucanVoting.VotingSettings memory) {
        uint32 ratioBase = uint32(RATIO_BASE);

        if (_settings.supportThreshold > ratioBase - 1) {
            _settings.supportThreshold = ratioBase - 1;
        }

        if (_settings.minParticipation > ratioBase) {
            _settings.minParticipation = ratioBase;
        }

        if (_settings.minDuration < 60 minutes) {
            _settings.minDuration = 60 minutes;
        }

        if (_settings.minDuration > 365 days) {
            _settings.minDuration = 365 days;
        }

        return _settings;
    }

    // test initial state: voting settings and DAO inc. event
    // getters return correct values
    // test supports iface
    /// -----------------------
    // updateVotingsettings:
    // requires permission
    // support threshold: ratio out of bounds
    // voting settings: ratio out of bounds
    // min duration < 60 minutes
    // min duration > 365 days
    // updates settings and emits the event
    /// ---------------------
    // has enough voting power:
    // total supply == 0 at snapshot block
    // has enough voting power
    // min proposer voting power > 0:
    // reverts if not enough voting power
    // balance/voting power or both
    // skips check if min voting power is 0
    /// -----------------------
    // validate propososal dates:
    // start == 0 returns current ts
    // start < current ts revers out of bounds
    // end == 0 returns earliest possible end date
    // end < earliest possible end date reverts
    // else returns start and end
    // start > end reverts
    /// ------------------
    // create proposal:
    // sets proposal data, emits event, increments id
    // if _votes > 0 calls vote else doesn't
    /// -----------------
    // is member:
    // has > 0 tokens
    // has > 0 delegated votes
    // both > 0
    // neither returns false
    /// -----------------
    // is proposal open:
    // open proposal (timestamp)
    // open but executed
}
