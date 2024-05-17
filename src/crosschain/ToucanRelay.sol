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
 * 3. User can change their vote (if not already dispatched)
 * 4. We can split a user's vote across y/n/a
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

    mapping(uint256 proposalId => TallyBatch) public batches;

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

    /// lastVoted == 0 means they haven't voted
    /// lastSent  == 0 means the proposal hasn't been dispatched
    /// lastVoted > lastSent, the user's most recent vote hasn't been dispatched and they can change their vote
    /// lastVote  < lastSent, the user's most recent vote has been dispatched and they can't change their vote
    struct LastVoteRecord {
        uint256 at;
        Tally votes;
    }

    /// groups the votes for a proposal. Allows for multiple batches to be sent.
    struct TallyBatch {
        // the last time we dispatched the votes - ensures we don't dispatch the same data twice
        uint256 lastSent;
        // the index of the last item we dispatched - ensures we know if we need to create a new batch
        uint256 lastSentIndex;
        // the aggregates of the votes, where each item is a batch
        Tally[] aggregates;
        // last vote a user made, required because we need to revert the old vote if they change it
        mapping(address voter => LastVoteRecord) voterLastVoted;
    }

    /// OApp but also tracks the voting token
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OApp(_lzEndpoint, _delegate) {
        token = Token(_token);
    }

    /// we need a new batch if:
    /// the aggregates array is of length x
    /// the lastSentIndex is x
    /// the lastSent is in the past
    /// so example: 10 items, lastSentIndex is 10, lastSent is in the past -> create the 11th item
    /// 11 items, lastSentIndex is 10, lastSent is in the past -> we haven't dispatched the 11th item yet
    function _needNewBatch(uint256 _proposalId) internal view returns (bool) {
        // if the aggregates array is empty then we need a new batch
        if (batches[_proposalId].aggregates.length == 0) {
            return true;
        }

        TallyBatch storage batch = batches[_proposalId];
        uint256 lengthOfAggregatesArray = batch.aggregates.length;
        bool lastSentIndexIsLast = batch.lastSentIndex == lengthOfAggregatesArray - 1;
        bool lastSentIsInPast = batch.lastSent > 0;
        return lastSentIndexIsLast && lastSentIsInPast;
    }

    /// vote on the L2
    function vote(Tally calldata _voteOptions, uint256 _proposalId) external {
        (, uint32 timestamp, ) = ProposalIdCodec.decode(_proposalId);

        require(timestamp < block.timestamp, "u can't vote in the future");

        uint256 abstentions = _voteOptions.abstain;
        uint256 yays = _voteOptions.yes;
        uint256 nays = _voteOptions.no;
        uint256 total = abstentions + yays + nays;

        require(total > 0, "u stupid?");

        // here we will need to do a proper "canVote" check
        // I think it can be largely lifted from TokenVoting
        // the thing to check is how we are computing the historical balance
        // as the timestamp of the proposal is the value that has meaning across chains
        require(total == token.balanceAt(msg.sender, timestamp), "u messin?");

        TallyBatch storage batch = batches[_proposalId];
        LastVoteRecord storage lastVoted = batch.voterLastVoted[msg.sender];

        if (lastVoted.at <= batch.lastSent) {
            revert("u already voted");
        }

        uint256 latestBatch = batch.aggregates.length - 1;

        // user has a previous vote that hasn't been dispatched yet
        if (lastVoted.at > batch.lastSent) {
            // revert the old vote
            Tally storage oldVote = lastVoted.votes;
            batch.aggregates[latestBatch].abstain -= oldVote.abstain;
            batch.aggregates[latestBatch].yes -= oldVote.yes;
            batch.aggregates[latestBatch].no -= oldVote.no;
        }

        // if there's no current batch then create a new one
        if (_needNewBatch(_proposalId)) {
            batch.aggregates.push(Tally(0, 0, 0));
        }

        // add the new vote data
        batch.aggregates[latestBatch].abstain += abstentions;
        batch.aggregates[latestBatch].yes += yays;
        batch.aggregates[latestBatch].no += nays;

        lastVoted.at = block.timestamp;
        lastVoted.votes = _voteOptions;

        // emit some data
    }

    /// This function will take the votes for a given proposal ID and dispatch them to the canonical chain
    function dispatchVotes(uint256 _proposalId) external {
        // get the proposal data
        // encode the proposal data
        // send the proposal data
        // (address plugin, , uint64 executionChainId) = ProposalIdCodec.decode(_proposalId);

        // get the aggregate data
        TallyBatch storage batch = batches[_proposalId];
        if (batch.aggregates.length == 0) {
            revert("no votes to send");
        }

        uint256 latestBatch = batch.aggregates.length - 1;
        require(latestBatch > batch.lastSentIndex, "u already sent this");

        // encode && send the data
        // lzSend(plugin, latestTally, executionChainId);
        batch.lastSent = block.timestamp;
        batch.lastSentIndex = latestBatch;
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
