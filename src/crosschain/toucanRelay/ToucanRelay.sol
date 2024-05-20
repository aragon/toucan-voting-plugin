pragma solidity ^0.8.20;

import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";
import {OAppSender, OAppCore} from "@lz-oapp/OAppSender.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {ProposalIdCodec} from "./ProposalIdCodec.sol";
import "utils/converters.sol";

// placeholder, we need a proper governance erc20
interface Token {
    function balanceAt(address account, uint timestamp) external view returns (uint256);
}

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
    /// placeholder will be a governance ERC20 token
    Token public token;

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
    function vote(
        Tally calldata _voteOptions,
        uint256 _proposalId,
        uint256 _executionChainId
    ) external {
        uint256 abstentions = _voteOptions.abstain;
        uint256 yays = _voteOptions.yes;
        uint256 nays = _voteOptions.no;
        uint256 total = abstentions + yays + nays;

        require(total > 0, "u stupid?");
        require(canVote(_proposalId, msg.sender, total), "u can't vote");

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
    ) external view returns (MessagingFee memory fee) {
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
        bytes memory message = abi.encode(
            ToucanVoteMessage(_chainId(), _proposalId, proposal.tally)
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gasLimit, 0);
        return _quote(_dstEid, message, options, false);
    }

    /// if you're on a chain that doesn't support 155 you can override this
    /// or if we decide to change the chainId mechanism we use
    function _chainId() internal view virtual returns (uint256) {
        return block.chainid;
    }
}
