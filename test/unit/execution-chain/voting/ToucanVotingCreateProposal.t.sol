// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";

import {TallyMath} from "@libs/TallyMath.sol";

import {createTestDAO} from "@mocks/MockDAO.sol";
import {deployMockToucanVoting} from "@utils/deployers.sol";
import {ToucanVotingTestBase} from "./ToucanVotingBase.t.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {_applyRatioCeiled, RatioOutOfBounds, RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";

contract TestToucanVotingCreateProposal is ToucanVotingTestBase {
    using TallyMath for Tally;

    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed creator,
        uint64 startDate,
        uint64 endDate,
        bytes metadata,
        IDAO.Action[] actions,
        uint256 allowFailureMap
    );

    function setUp() public override {
        super.setUp();
        // snapshot requires >= 1 block/ts
        vm.roll(1);
        vm.warp(1);
    }

    function test_cannotCreateProposalWithZeroSupply() public {
        vm.expectRevert(abi.encodeWithSelector(ToucanVoting.NoVotingPower.selector));
        _createDefaultProposal();
    }

    function testFuzz_cannotCreateProposalWithInsufficientVotingPower(
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

        token.mint(address(this), _tokenQty);
        token.delegate(_who);

        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ToucanVoting.ProposalCreationForbidden.selector, _who)
        );
        vm.startPrank(_who);
        {
            _createDefaultProposal();
        }
        vm.stopPrank();
    }

    // see separate test file for full testing of date boundaries
    function test_cannotCreateWithDateOutOfBounds() public {
        // end is < min duration
        uint32 start = uint32(block.timestamp + 1);
        uint32 end = uint32(block.timestamp + 2);

        // mint so we bypass zero supply check
        token.mint(address(this), 1 ether);
        vm.roll(block.number + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ToucanVoting.DateOutOfBounds.selector, start + MIN_DURATION, end)
        );
        voting.createProposal({
            _metadata: "",
            _actions: new IDAO.Action[](0),
            _allowFailureMap: 0,
            _startDate: start,
            _endDate: end,
            _votes: Tally(0, 0, 0),
            _tryEarlyExecution: false
        });
    }

    // TODO this could be a better test if we separated canCreate from the internal create
    function testFuzz_createsProposal(
        bytes memory _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap
    ) public {
        Tally memory _votes = Tally(0, 0, 0);

        // mint so we can vote
        token.mint(address(this), 1 ether);
        vm.roll(block.number + 1);

        vm.expectEmit(true, true, false, true);
        emit ProposalCreated({
            proposalId: 0,
            creator: address(this),
            startDate: uint64(block.timestamp),
            endDate: uint64(block.timestamp + MIN_DURATION),
            metadata: _metadata,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
        uint256 proposalId = voting.createProposal({
            _metadata: _metadata,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap,
            _startDate: 0,
            _endDate: 0,
            _votes: _votes,
            _tryEarlyExecution: false
        });

        // check proposal
        (
            bool open,
            bool executed,
            IToucanVoting.ProposalParameters memory parameters,
            Tally memory tally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        ) = voting.getProposal(proposalId);

        assertEq(open, true);
        assertEq(executed, false);
        assertEq(uint8(parameters.votingMode), uint8(IToucanVoting.VotingMode.Standard));
        assertEq(parameters.supportThreshold, SUPPORT_THRESHOLD);
        assertEq(parameters.minVotingPower, _applyRatioCeiled(1 ether, voting.minParticipation()));
        assertEq(parameters.snapshotBlock, block.number - 1);
        assertEq(parameters.snapshotTimestamp, block.timestamp - 1);
        assertEq(parameters.startDate, block.timestamp);
        assertEq(parameters.endDate, block.timestamp + MIN_DURATION);
        assertEq(allowFailureMap, _allowFailureMap);
        assertTrue(tally.isZero());
        assertEq(actions.length, _actions.length);
    }

    function _createDefaultProposal() internal returns (uint256) {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        Tally memory tally = Tally(0, 0, 0);
        return
            voting.createProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0,
                _startDate: 0,
                _endDate: 0,
                _votes: tally,
                _tryEarlyExecution: false
            });
    }
}
