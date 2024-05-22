pragma solidity ^0.8.20;

import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";
import {OAppSender, OAppCore} from "@lz-oapp/OAppSender.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ProposalIdCodec} from "./ProposalIdCodec.sol";
import "utils/converters.sol";
import "forge-std/console2.sol";

interface IToucanRelayMessage {
    struct ToucanVoteMessage {
        uint256 srcChainId;
        uint256 proposalId;
        IVoteContainer.Tally votes;
    }
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
 * NOTE: the relay as it currently stands is an OAppSender, so cannot currently receive messages
 */
contract ToucanRelay is OAppSender, IVoteContainer, IToucanRelayMessage {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;
    /// placeholder will be a governance ERC20 token
    IVotes public token;

    /// IDEA: set a default chainID and use that if you don't pass one
    /// this is a layerZero app, so maybe we can use the eid on layer zero...
    mapping(uint executionChainId => mapping(uint256 proposalId => Proposal)) public proposals;

    /// Voting chain only needs a subset of the data on the main plugin
    struct Proposal {
        Tally tally;
        mapping(address voter => Tally lastVote) voters;
    }

    struct LzSendParams {
        uint32 dstEid;
        uint128 gasLimit;
        MessagingFee fee;
    }

    /// OApp but also tracks the voting token
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OAppCore(_lzEndpoint, _delegate) {
        token = IVotes(_token);
    }

    function canVote(
        uint256 _proposalId,
        address _voter,
        Tally memory _voteOptions
    ) public view returns (bool) {
        return _canVote(_proposalId, _voter, _voteOptions);
    }

    function _canVote(
        uint256 _proposalId,
        address _account,
        Tally memory _voteOptions
    ) internal view returns (bool) {
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen({_startTs: startTimestamp, _endTs: endTimestamp})) {
            return false;
        }

        // this could re-enter with a malicious governance token
        uint votingPower = token.getPastVotes(_account, startTimestamp);

        // The voter has no voting power.
        if (votingPower == 0) {
            return false;
        }

        // the user has insufficient voting power to vote
        if (_totalVoteWeight(_voteOptions) > votingPower) {
            return false;
        }

        // At the moment, we always allow vote replacement. This could be changed in the future.

        return true;
    }

    function getVotes(
        uint256 _executionChainId,
        uint256 _proposalId,
        address _voter
    ) external view returns (Tally memory) {
        return proposals[_executionChainId][_proposalId].voters[_voter];
    }

    // there is no way of knowing if the proposal has been executed in this implementation
    // without receipt from the L1. Maybe we should deploy the OApp as a receveier to anticipate this functionality
    function _isProposalOpen(uint32 _startTs, uint32 _endTs) internal view virtual returns (bool) {
        // somewhat redundant check on ts overflow but these are L2s so who knows what crazy shit they do
        uint32 currentTime = block.timestamp.toUint32();

        // ERC20 votes requires > _startTs - I think this is different to the block but need to check
        return _startTs < currentTime && currentTime < _endTs;
    }

    function _totalVoteWeight(Tally memory _voteOptions) internal pure virtual returns (uint256) {
        return _voteOptions.yes + _voteOptions.no + _voteOptions.abstain;
    }

    /// vote on the L2
    function vote(
        uint256 _proposalId,
        uint256 _executionChainId,
        Tally calldata _voteOptions
    ) external {
        uint256 abstentions = _voteOptions.abstain;
        uint256 yays = _voteOptions.yes;
        uint256 nays = _voteOptions.no;
        uint256 total = abstentions + yays + nays;

        require(total > 0, "u stupid?");
        require(canVote(_proposalId, msg.sender, _voteOptions), "u can't vote");

        // get the proposal data
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
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
    function dispatchVotes(
        uint256 _proposalId,
        uint _executionChainId,
        LzSendParams memory _params
    ) external payable {
        // get the proposal data
        Proposal storage proposal = proposals[_executionChainId][_proposalId];

        // get the proposal data
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        // check the timestamp
        require(startTimestamp < block.timestamp, "u can't vote in the future");
        require(endTimestamp > block.timestamp, "u can't vote in the past");

        // check the proposal has some data
        require(proposal.tally.abstain + proposal.tally.yes + proposal.tally.no > 0, "u stupid?");

        bytes memory message = abi.encode(
            ToucanVoteMessage(_chainId(), _proposalId, proposal.tally)
        );

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
            _params.gasLimit,
            0
        );

        // refund should be somewhere safe on the dst chain
        // default to the peer address
        // need to add a sweep function to recover refunds
        address refundAddress = bytes32ToAddress(peers[_params.dstEid]);

        // dispatch the votes
        _lzSend(_params.dstEid, message, options, _params.fee, refundAddress);
    }

    function quote(
        uint256 _proposalId,
        uint _executionChainId,
        uint32 _dstEid,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
        bytes memory message = abi.encode(
            ToucanVoteMessage(_chainId(), _proposalId, proposal.tally)
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gasLimit, 0);
        MessagingFee memory fee = _quote(_dstEid, message, options, false);
        return LzSendParams({dstEid: _dstEid, gasLimit: _gasLimit, fee: fee});
    }

    /// if you're on a chain that doesn't support 155 you can override this
    /// or if we decide to change the chainId mechanism we use
    function _chainId() internal view virtual returns (uint256) {
        return block.chainid;
    }
}
