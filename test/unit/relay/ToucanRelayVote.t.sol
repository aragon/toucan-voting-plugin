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
contract TestToucanRelayVote is ToucanRelayBaseTest {
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();
    }

    /// @param executionChainId randomised execution chain id for use in test
    /// @param proposalId randomised proposal id for use in test
    /// @param voter randomised voter address for use in test, must not be address(0)
    /// @param warpTo timestamp to warp to
    /// @param mintQty amount of governance tokens to mint to the voter
    /// @param voteOptions the combo of y/n/a votes to cast
    struct State {
        uint256 executionChainId;
        uint256 proposalId;
        address voter;
        uint32 warpTo;
        uint224 mintQty;
        Tally voteOptions;
    }

    // a single user can vote against 1 proposal
    function testFuzz_singleVoterSingleProposal(State memory _state) public {
        _validateAndInitializeState(_state);

        // vote
        vm.prank(_state.voter);
        relay.vote(_state.executionChainId, _state.proposalId, _state.voteOptions);

        // check the vote
        Tally memory votes = relay.getVotes(
            _state.executionChainId,
            _state.proposalId,
            _state.voter
        );
        assert(votes.eq(_state.voteOptions));

        // check the proposal
        Tally memory proposalVotes = relay.proposals(_state.executionChainId, _state.proposalId);
        assert(proposalVotes.eq(_state.voteOptions));
    }

    // the user can update their vote correctly
    function testFuzz_userCanUpdateVote(State memory _state) public {
        _validateAndInitializeState(_state);

        // vote
        vm.prank(_state.voter);
        relay.vote(_state.executionChainId, _state.proposalId, _state.voteOptions);

        // check the vote
        Tally memory votes = relay.getVotes(
            _state.executionChainId,
            _state.proposalId,
            _state.voter
        );
        assert(votes.eq(_state.voteOptions));

        // check the proposal
        Tally memory proposalVotes = relay.proposals(_state.executionChainId, _state.proposalId);
        assert(proposalVotes.eq(_state.voteOptions));

        // update the vote, must ensure same voting power
        uint total = _state.voteOptions.sum();
        Tally memory newVoteOptions = Tally({yes: total / 3, no: total / 3, abstain: total / 3});
        // avoid zero votes due to integer division
        if (newVoteOptions.sum() == 0) {
            newVoteOptions.yes = 1;
        }

        // vote
        vm.prank(_state.voter);
        relay.vote(_state.executionChainId, _state.proposalId, newVoteOptions);

        // check the vote
        votes = relay.getVotes(_state.executionChainId, _state.proposalId, _state.voter);
        assert(votes.eq(newVoteOptions));

        // check the proposal
        proposalVotes = relay.proposals(_state.executionChainId, _state.proposalId);
        assert(proposalVotes.eq(newVoteOptions));
    }

    // multiple users can vote on the same proposal
    function testFuzz_multipleVotersSingleProposal(State memory _stateFirst) public {
        // check this first to avoid later overflow
        vm.assume(!_stateFirst.voteOptions.overflows());

        // avoid overflows when both qtys get added
        vm.assume(_stateFirst.mintQty <= type(uint216).max);
        vm.assume(_stateFirst.voteOptions.sum() <= _stateFirst.mintQty);
        vm.assume(_stateFirst.voteOptions.sum() > 0);

        // ERC20 prevents minting to zero address
        vm.assume(_stateFirst.voter != address(0));

        // make the second voter a valid transformation of the first
        State memory _stateSecond;
        {
            _stateSecond.voter = _hashAddress(_stateFirst.voter);
            // mint half the amount of the first, but as we will split into 3, add 3 to avoid zero votes
            _stateSecond.mintQty = (_stateFirst.mintQty / 2) + 3;
            _stateSecond.voteOptions = Tally({
                yes: _stateSecond.mintQty / 3,
                no: _stateSecond.mintQty / 3,
                abstain: _stateSecond.mintQty / 3
            });
        }

        token.mint({to: _stateFirst.voter, amount: _stateFirst.mintQty});
        token.mint({to: _stateSecond.voter, amount: _stateSecond.mintQty});

        _warpToValidTs(_stateFirst.proposalId, _stateFirst.warpTo);

        // vote person A
        vm.prank(_stateFirst.voter);
        relay.vote(_stateFirst.executionChainId, _stateFirst.proposalId, _stateFirst.voteOptions);

        // vote person B
        vm.prank(_stateSecond.voter);
        relay.vote(_stateFirst.executionChainId, _stateFirst.proposalId, _stateSecond.voteOptions);

        // check the vote person A
        Tally memory votesA = relay.getVotes(
            _stateFirst.executionChainId,
            _stateFirst.proposalId,
            _stateFirst.voter
        );
        assert(votesA.eq(_stateFirst.voteOptions));

        // check the vote person B - note that we use state A for ids
        Tally memory votesB = relay.getVotes(
            _stateFirst.executionChainId,
            _stateFirst.proposalId,
            _stateSecond.voter
        );
        assert(votesB.eq(_stateSecond.voteOptions));

        // the proposal should have the sum of the votes
        Tally memory actualProposalVotes = relay.proposals(
            _stateFirst.executionChainId,
            _stateFirst.proposalId
        );
        Tally memory expectedProposalVotes = _stateFirst.voteOptions.add(_stateSecond.voteOptions);
        assert(actualProposalVotes.eq(expectedProposalVotes));
    }

    // the user can vote against multiple proposals
    function testFuzz_singleVoterMultipleProposals(
        State memory _stateFirst,
        State memory _stateSecond
    ) public {
        // hard one to test many states - better for an invariant test most likely
    }

    function _validateAndInitializeState(State memory _state) internal {
        // sum of votes must not overflow
        vm.assume(!_state.voteOptions.overflows());

        // ERC20 prevents minting to zero address
        vm.assume(_state.voter != address(0));

        // we want this to be a valid vote
        vm.assume(_state.voteOptions.sum() <= _state.mintQty);
        vm.assume(_state.voteOptions.sum() > 0);

        // note the order of the calls
        token.mint({to: _state.voter, amount: _state.mintQty});
        _warpToValidTs(_state.proposalId, _state.warpTo);
    }

    function _hashAddress(address _address) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encode(_address)))));
    }
}
