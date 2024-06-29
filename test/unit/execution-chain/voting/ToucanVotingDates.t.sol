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

contract TestToucanVotingDates is ToucanVotingTestBase {
    function testFuzz_zeroesReturnDefaults(uint32 _warpTo, uint32 _minDuration) public {
        vm.assume(_minDuration <= 365 days && _minDuration >= 60 minutes);
        vm.assume(uint(_warpTo) + uint(_minDuration) < type(uint32).max);
        vm.warp(_warpTo);

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minDuration = _minDuration;
        voting.updateVotingSettings(settings);
        (uint32 start, uint32 end) = voting.validateProposalDates(0, 0);

        assertEq(start, _warpTo);
        assertEq(end, start + _minDuration);
    }

    // start < current ts revers out of bounds
    function testFuzz_startBeforeCurrent(uint32 _start, uint32 _end, uint32 _warpTo) public {
        vm.assume(_start > 0);
        vm.assume(_start < _warpTo);

        vm.warp(_warpTo);

        vm.expectRevert(
            abi.encodeWithSelector(ToucanVoting.DateOutOfBounds.selector, block.timestamp, _start)
        );
        voting.validateProposalDates(_start, _end);
    }

    // end < earliest possible end date reverts
    function testFuzz_endBeforeMinDuration(
        uint32 _start,
        uint32 _end,
        uint32 _minDuration,
        uint32 _warpTo
    ) public {
        vm.assume(_end > 0);
        vm.assume(_start >= _warpTo);
        vm.assume(_minDuration <= 365 days && _minDuration >= 60 minutes);
        vm.assume(uint(_start) + uint(_minDuration) <= type(uint32).max);
        vm.assume(_end < _start + _minDuration);

        vm.warp(_warpTo);

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minDuration = _minDuration;
        voting.updateVotingSettings(settings);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToucanVoting.DateOutOfBounds.selector,
                _start + _minDuration,
                _end
            )
        );
        voting.validateProposalDates(_start, _end);
    }

    // start > end reverts
    function testFuzz_startAfterEnd(uint32 _start, uint32 _end) public {
        vm.assume(_start >= block.timestamp);
        vm.assume(_end > 0);
        vm.assume(_start > _end);
        vm.assume(uint(_start) + uint(MIN_DURATION) <= type(uint32).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                ToucanVoting.DateOutOfBounds.selector,
                _start + MIN_DURATION,
                _end
            )
        );
        voting.validateProposalDates(_start, _end);
    }

    // else returns start and end
    function test_validDates(
        uint32 _start,
        uint32 _end,
        uint32 _minDuration,
        uint32 _warpTo
    ) public {
        vm.assume(_end > 0);
        vm.assume(_start >= _warpTo);
        vm.assume(_minDuration <= 365 days && _minDuration >= 60 minutes);
        vm.assume(uint(_start) + uint(_minDuration) <= type(uint32).max);
        vm.assume(_end >= _start + _minDuration);

        vm.warp(_warpTo);

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minDuration = _minDuration;
        voting.updateVotingSettings(settings);

        (uint32 start, uint32 end) = voting.validateProposalDates(_start, _end);
        assertEq(start, _start);
        assertEq(end, _end);
    }
}
