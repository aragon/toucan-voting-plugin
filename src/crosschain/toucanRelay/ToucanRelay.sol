pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

/// Codec because it makes me feel fancy and layer zero chads do it.
library ProposalIdCodec {
    // we have 32 bits of unused space
    function encode(
        address _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp
    ) internal pure returns (uint256 proposalId) {
        uint256 addr = uint256(uint160(_plugin));
        return
            (addr << 96) |
            (uint256(_proposalStartTimestamp) << 64) |
            ((uint256(_proposalEndTimestamp)) << 32);
        // 32 bits of unused space
    }

    function decode(
        uint256 _proposalId
    ) internal pure returns (address plugin, uint32 startTimestamp, uint32 endtimestamp) {
        // shift out the redundant bits then cast to the correct type
        plugin = address(uint160(_proposalId >> 96));
        startTimestamp = uint32(_proposalId >> 64);
        endtimestamp = uint32(_proposalId >> 32);
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
 *
 * On L2 voting we have a few requirements:
 * 1. User can vote and this will be aggregated.
 * 2. We can dispatch the votes to the canonical chain
 * 3. User can change their vote (if the proposal has not ended)
 * 4. We can split a user's vote across y/n/a
 * 5. Users can partial vote
 *
 *
 * Allowing them to change & split votes requires storing the history so we can revert the past vote
 * and apply the new one.
 *
 */
contract ToucanRelay is OApp {
    /// placeholder will be a governance ERC20 token
    Token public token;

    /// placeholder - the received in lzReceive
    bool public received;

    /// @notice A mapping between proposal IDs and proposal information.
    /// @dev I think we might need to go one level deeper and store it as
    /// mapping(uint chainId => mapping(uint256 proposalId => Proposal) proposals;
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
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        require(startTimestamp < block.timestamp, "u can't vote in the future");
        require(endTimestamp > block.timestamp, "u can't vote in the past");
        // here we will need to do a proper "canVote" check
        // I think it can be largely lifted from TokenVoting
        // the thing to check is how we are computing the historical balance
        // as the timestamp of the proposal is the value that has meaning across chains
        require(_total <= token.balanceAt(_voter, startTimestamp), "u messin?");

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
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        // check the timestamp
        require(startTimestamp < block.timestamp, "u can't vote in the future");

        require(endTimestamp > block.timestamp, "u can't vote in the past");

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
