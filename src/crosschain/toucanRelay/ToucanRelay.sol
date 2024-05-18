pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

/// proposalId is the plugin address + timestamp + chainId
/// Codec because it makes me feel fancy and layer zero chads do it.
library ProposalIdCodec {
    function encode(
        address _plugin,
        /* should we have  close timestamp? */
        uint32 _timestamp,
        uint64 _executionChainId
    ) internal pure returns (uint256 proposalId) {
        uint256 addr = uint256(uint160(_plugin));
        // the timestamp being 32 bits and chain id being 64 bits makes me wonder if we could have a 32 bit
        // chain ID and store the close timestamp as well?
        return (addr << 96) | (uint256(_timestamp) << 64) | uint256(_executionChainId);
    }

    function decode(
        uint256 _proposalId
    ) internal pure returns (address plugin, uint32 timestamp, uint64 executionChainId) {
        // shift out the redundant bits then cast to the correct type
        plugin = address(uint160(_proposalId >> 96));
        timestamp = uint32(_proposalId >> 64);
        executionChainId = uint64(_proposalId);
    }
}

// placeholder, we need a proper governance erc20
interface Token {
    function balanceAt(address account, uint timestamp) external view returns (uint256);
}

/**
 * the relay contract serves as the bridge back to the canonical chain.
 *
 * The relay has a few responsibilites
 *
 * 1. It stores vote data until such data can be dispatched cross chain
 * 2. It validates the data it stores, checking that the timestamp passed is valid
 * 3. It can receive a proposal timestamp for additional validation
 *
 * On L2 voting we have a few requirements:
 * 1. User can vote and this will be aggregated.
 * 2. We can dispatch the votes to the canonical chain
 * 3. User can change their vote (if the proposal has not ended)
 * 4. We can split a user's vote across y/n/a
 * 5. Users
 *
 *
 * Allowing them to change & split votes requires storing the history so we can revert the past vote
 * and apply the new one.
 *
 * We also need to store WHEN the vote was cast so we can see if the vote has been dispatched
 */
contract ToucanRelay is OApp {
    /// placeholder will be a governance ERC20 token
    Token public token;

    /// placeholder - the received in lzReceive
    bool public received;

    /// @notice A mapping between proposal IDs and proposal information.
    mapping(uint256 proposalId => Proposal) public proposals;

    /// @notice A container for the proposal vote tally
    /// @dev Used in aggregate across a proposal as well as per user
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    /// Voting chain only needs a subset of the data on the main plugin
    struct Proposal {
        Tally tally;
        mapping(address voter => Tally lastVote) voters;
    }

    /// OApp but also tracks the voting token
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OApp(_lzEndpoint, _delegate) {
        token = Token(_token);
    }

    function canVote(uint256 _proposalId, address _voter, uint _total) public view returns (bool) {
        (, uint32 timestamp, ) = ProposalIdCodec.decode(_proposalId);

        require(timestamp < block.timestamp, "u can't vote in the future");
        // here we will need to do a proper "canVote" check
        // I think it can be largely lifted from TokenVoting
        // the thing to check is how we are computing the historical balance
        // as the timestamp of the proposal is the value that has meaning across chains
        require(_total <= token.balanceAt(_voter, timestamp), "u messin?");

        return true;
    }

    /// vote on the L2
    function vote(Tally calldata _voteOptions, uint256 _proposalId) external {
        uint256 abstentions = _voteOptions.abstain;
        uint256 yays = _voteOptions.yes;
        uint256 nays = _voteOptions.no;
        uint256 total = abstentions + yays + nays;

        require(total > 0, "u stupid?");
        require(canVote(_proposalId, msg.sender, total), "u can't vote");

        // get the proposal data
        Proposal storage proposal = proposals[_proposalId];
        Tally storage lastVote = proposal.voters[msg.sender];

        // revert the last vote
        proposal.tally.abstain -= lastVote.abstain;
        proposal.tally.yes -= lastVote.yes;
        proposal.tally.no -= lastVote.no;

        // update the last vote
        lastVote.abstain = _voteOptions.abstain;
        lastVote.yes = _voteOptions.yes;
        lastVote.no = _voteOptions.no;

        // update the total vote
        proposal.tally.abstain += abstentions;
        proposal.tally.yes += yays;
        proposal.tally.no += nays;

        // emit some data
    }

    /// This function will take the votes for a given proposal ID and dispatch them to the canonical chain
    function dispatchVotes(uint256 _proposalId) external {
        // get the proposal data
        Proposal storage proposal = proposals[_proposalId];

        // get the proposal data
        (address plugin, uint32 timestamp, uint64 chainId) = ProposalIdCodec.decode(_proposalId);

        // check the timestamp
        require(timestamp < block.timestamp, "u can't vote in the future");

        // check the proposal has some data
        require(proposal.tally.abstain + proposal.tally.yes + proposal.tally.no > 0, "u stupid?");

        // dispatch the votes
        // this will be a call to the canonical chain
        // lzSend(*args)
    }

    /// @dev placeholder for the lzReceive function
    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal override {
        received = true;
    }
}
