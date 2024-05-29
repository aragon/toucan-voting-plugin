// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "src/token/governance/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import "@libs/TallyMath.sol";

import {Test} from "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";

import {deployToucanRelay} from "utils/deployers.sol";
import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanRelayCanVote is ToucanRelayBaseTest {
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();
    }

    // test can vote:
    function testFuzz_cannotVoteBeforeStart(
        uint256 _proposalId,
        address _voter,
        Tally memory _voteOptions,
        uint32 _warpTo
    ) public {
        // decode existing random proposal id
        (, uint32 _startTs, ) = ProposalIdCodec.decode(_proposalId);

        // assume that the startTs is greater than or equal the block ts we will move to
        vm.assume(_startTs >= _warpTo);

        // warp to the start
        vm.warp(_warpTo);

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertFalse(canVote);
    }

    function testFuzz_cannotVoteAfterEnd(
        uint256 _proposalId,
        address _voter,
        Tally memory _voteOptions,
        uint32 _warpTo
    ) public {
        // decode existing random proposal id
        (, , uint32 _endTs) = ProposalIdCodec.decode(_proposalId);

        // assume that the endTs is less than or equal the block ts we will move to
        vm.assume(_endTs <= _warpTo);

        // warp to the end
        vm.warp(_warpTo);

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertFalse(canVote);
    }

    // cannot vote if user is trying to vote with zero tokens
    function testFuzz_cannotVoteWithZeroWeight(
        uint256 _proposalId,
        address _voter,
        uint32 _warpTo
    ) public {
        _warpToValidTs(_proposalId, _warpTo);

        // set the weight to zero
        Tally memory _voteOptions = Tally({yes: 0, no: 0, abstain: 0});

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertFalse(canVote);
    }

    // false if the user has too little voting power at the startTs, lte startTs
    function testFuzz_cannotVoteWithInsufficientWeight(
        uint256 _proposalId,
        address _voter,
        uint32 _warpTo,
        uint224 _mintQty /* this is the max value that can fit in ERC20 Votes */,
        Tally memory _voteOptions
    ) public {
        // TODO: do we want to explicitly check for this?
        vm.assume(!_voteOptions.overflows());

        // ERC20 prevents minting to zero address
        vm.assume(_voter != address(0));

        // this is the test case where the user has too little voting power at the startTs
        vm.assume(_voteOptions.sum() > _mintQty);

        // note the order of the calls
        token.mint({to: _voter, amount: _mintQty});
        _warpToValidTs(_proposalId, _warpTo);

        // set the weight to zero
        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertFalse(canVote);
    }

    // above holds even if the user gets voting power after the startTs
    function testFuzz_cannotVoteWithInsufficientWeightAfterTransfer(
        uint256 _proposalId,
        address _voter,
        uint32 _warpTo,
        uint224 _mintQty /* this is the max value that can fit in ERC20 Votes */,
        Tally memory _voteOptions
    ) public {
        vm.assume(!_voteOptions.overflows());

        // ERC20 prevents minting to zero address
        vm.assume(_voter != address(0));

        // we want this to be an otherwise valid vote
        vm.assume(_voteOptions.sum() <= _mintQty);

        // note the order of the calls
        _warpToValidTs(_proposalId, _warpTo);
        // could just as easily be a transfer
        token.mint({to: _voter, amount: _mintQty});

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertFalse(canVote);
    }

    // true for all ts between the start and end block, if the user has enough voting power
    function testFuzz_canVoteIfHasEnoughVotingPowerAndValidTs(
        uint256 _proposalId,
        address _voter,
        uint32 _warpTo,
        uint224 _mintQty /* this is the max value that can fit in ERC20 Votes */,
        Tally memory _voteOptions
    ) public {
        vm.assume(!_voteOptions.overflows());

        // ERC20 prevents minting to zero address
        vm.assume(_voter != address(0));

        // we want this to be a valid vote
        vm.assume(_voteOptions.sum() <= _mintQty);
        vm.assume(_voteOptions.sum() > 0);

        // note the order of the calls
        token.mint({to: _voter, amount: _mintQty});
        _warpToValidTs(_proposalId, _warpTo);

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertTrue(canVote);
    }

    // works even if a user has transferred voting power after the startTs
    function testFuzz_canVoteIfHasEnoughVotingPowerAfterTransferAndValidTs(
        uint256 _proposalId,
        address _voter,
        uint32 _warpTo,
        uint224 _mintQty /* this is the max value that can fit in ERC20 Votes */,
        Tally memory _voteOptions
    ) public {
        vm.assume(!_voteOptions.overflows());

        // ERC20 prevents minting to zero address
        vm.assume(_voter != address(0));

        // we want this to be a valid vote
        vm.assume(_voteOptions.sum() <= _mintQty);
        vm.assume(_voteOptions.sum() > 0);

        // note the order of the calls
        token.mint({to: _voter, amount: _mintQty});
        _warpToValidTs(_proposalId, _warpTo);

        // give the tokens away
        vm.prank(_voter);
        token.transfer({to: address(this), amount: _mintQty});

        bool canVote = relay.canVote({
            _proposalId: _proposalId,
            _voter: _voter,
            _voteOptions: _voteOptions
        });
        assertTrue(canVote);
    }
}
