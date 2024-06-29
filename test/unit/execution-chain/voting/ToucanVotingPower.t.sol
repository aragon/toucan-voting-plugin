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

contract TestToucanVotingPower is ToucanVotingTestBase {
    function test_votingPowerTrueIfMinProposerVotingPowerIsZero(address _who) public {
        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minProposerVotingPower = 0;
        voting.updateVotingSettings(settings);

        assertTrue(voting.hasEnoughVotingPower(_who));
    }

    function testFuzz_insufficientVotingPower(
        address _who,
        uint224 _tokenQty,
        uint224 _minVotingPower
    ) public {
        vm.assume(_minVotingPower > 0);
        vm.assume(_tokenQty < _minVotingPower);
        vm.assume(_tokenQty > 0);

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minProposerVotingPower = _minVotingPower;
        voting.updateVotingSettings(settings);

        token.mint(address(this), _tokenQty);
        token.delegate(_who);

        vm.roll(2);

        assertFalse(voting.hasEnoughVotingPower(_who));
    }

    function testFuzz_insufficientBalance(
        address _who,
        uint224 _tokenQty,
        uint224 _minVotingPower
    ) public {
        vm.assume(_minVotingPower > 0);
        vm.assume(_tokenQty < _minVotingPower);
        vm.assume(_tokenQty > 0);
        vm.assume(_who != address(0));

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minProposerVotingPower = _minVotingPower;
        voting.updateVotingSettings(settings);

        token.mint(address(_who), _tokenQty);

        assertFalse(voting.hasEnoughVotingPower(_who));
    }

    function testFuzz_insufficientBalanceSufficientVotingPower(
        address _who,
        uint224 _tokenQty,
        uint224 _minVotingPower
    ) public {
        vm.assume(_minVotingPower > 0);
        vm.assume(_tokenQty < _minVotingPower);
        vm.assume(_tokenQty > 0);
        vm.assume(_who != address(0));

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minProposerVotingPower = _minVotingPower;
        voting.updateVotingSettings(settings);

        token.mint(address(this), _minVotingPower);
        token.delegate(_who);

        assertTrue(voting.hasEnoughVotingPower(_who));
    }

    function testFuzz_sufficientBalance(
        address _who,
        uint224 _tokenQty,
        uint224 _minVotingPower
    ) public {
        vm.assume(_minVotingPower > 0);
        vm.assume(_tokenQty >= _minVotingPower);
        vm.assume(_who != address(0));

        IToucanVoting.VotingSettings memory settings = _defaultVotingSettings();
        settings.minProposerVotingPower = _minVotingPower;
        voting.updateVotingSettings(settings);

        token.mint(address(_who), _tokenQty);

        assertTrue(voting.hasEnoughVotingPower(_who));
    }
}
