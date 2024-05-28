// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanRelayMessage} from "@interfaces/IToucanRelayMessage.sol";

import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";
import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import "utils/converters.sol";
import "forge-std/console2.sol";

/// @title ToucanRelay
/// @author Aragon
/// @notice A cross chain relayer for aggregating votes on a voting chain and dispatching to an execution chain.
///
/// The relayer has a few responsibilites
///
/// 1. It stores vote data until such data can be dispatched cross chain
/// 2. It validates the data it stores, checking that the timestamp passed is valid
///
/// On the voting chain we have a few requirements:
/// 1. User can vote and this will be aggregated.
/// 2. We can dispatch the votes to the execution chain
/// 3. User can change their vote (if the proposal has not ended)
/// 4. We can split a user's vote across y/n/a
/// 5. Users can partial vote
contract ToucanRelay is OApp, IVoteContainer, IToucanRelayMessage, DaoAuthorizable {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    /// @notice Subset of proposal data seen required to dispatch votes cross chain.
    /// @param tally Aggregated votes for the proposal.
    /// @param voters Mapping of voters to their most recent vote choices.
    struct Proposal {
        Tally tally;
        mapping(address voter => Tally lastVote) voters;
    }

    /// @notice Additional Layer Zero params required to send a cross chain message.
    /// @param dstEid The LayerZero endpoint ID of the execution chain.
    /// @param gasLimit The additional gas needed on the execution chain to process the message, surplus will be refunded.
    /// @param fee The messaging fee required to send the message, this is sent to LayerZero.
    /// @param options Additional options required to send the message, these are encoded as bytes.
    struct LzSendParams {
        uint32 dstEid;
        uint128 gasLimit;
        MessagingFee fee;
        bytes options;
    }

    /// ---------- ERRORS ---------

    /// @notice Thrown if this OAapp cannot receive messages.
    error CannotReceive();

    /// @notice Thrown if the voter tries to cast a vote with zero voting weight.
    error CannotVoteZero(uint executionChainId, uint256 proposalId, address voter);

    /// @notice Thrown if the voter fails the `canVote` check during the voting process.
    error CannotVote(uint executionChainId, uint256 proposalId, address voter, Tally voteOptions);

    /// @notice Thrown if the proposal has no votes assosciated with it.
    error NoVotesToDispatch(uint256 executionChainId, uint256 proposalId);

    /// @notice Thrown if the proposal start time indicates that it is not open for voting.
    error ProposalNotOpen(uint256 executionChainId, uint256 proposalId, uint32 openAt);

    /// @notice Thrown if the proposal end time indicates that it is already closed for voting.
    error ProposalAlreadyClosed(uint256 executionChainId, uint256 proposalId, uint32 closedAt);

    /// ---------- EVENTS --------

    /// @notice Emitted when a voter successfully casts a vote on a proposal.
    event VoteCast(
        uint256 indexed executionChainId,
        uint256 indexed proposalId,
        address voter,
        Tally voteOptions
    );

    /// @notice Emitted when anyone dispatches the votes for a proposal to the execution chain.
    event VotesDispatched(
        uint256 indexed executionChainId,
        uint256 indexed proposalId,
        Tally votes
    );

    /// ---------- STATE ----------

    /// @notice The voting token used by the relay. Must use a timestamp based clock on the voting chain.
    IVotes public token;

    /// @notice The proposals are stored in a nested mapping by execution chain and proposal ID.
    /// @dev TODO: whether or not we should store against the layerZero EID instead of the execution chain ID.
    mapping(uint256 executionChainId => mapping(uint256 proposalId => Proposal)) public proposals;

    /// -------- MODIFIERS --------

    /// @dev can probably replace this with OZ
    bool public guard = false;
    error NoReentrant();
    modifier noReentrant() {
        if (guard) revert NoReentrant();
        guard = true;
        _;
        guard = false;
    }

    /// --------- CONSTRUCTOR ---------

    /// @param _token The voting token used by the relay. Should be a timestamp based voting token.
    /// @param _lzEndpoint The LayerZero endpoint address for the relay on this chain.
    /// @param _dao The DAO address that will be the owner of this relay and will control permissions.
    constructor(
        address _token,
        address _lzEndpoint,
        address _dao
    ) OApp(_lzEndpoint, _dao) DaoAuthorizable(IDAO(_dao)) {
        token = IVotes(_token);
    }

    /// -------- STATE MODIFYING FUNCTIONS --------

    /// @notice Anyone with a voting token that has voting power can vote on a proposal.
    /// @param _executionChainId The chain ID where the proposal will be executed.
    /// @param _proposalId The proposal ID to vote on. Must be fetched from the Execution Chain
    /// as it is not validated here.
    /// @param _voteOptions Votes split between yes no and abstain up to the voter's total voting power.
    function vote(
        uint256 _executionChainId,
        uint256 _proposalId,
        Tally calldata _voteOptions
    ) external noReentrant {
        uint256 abstentions = _voteOptions.abstain;
        uint256 yays = _voteOptions.yes;
        uint256 nays = _voteOptions.no;

        // for extremely large voting totals, we will revert on overflow trying to sum the votes
        // so better to check each weight individually
        if (abstentions == 0 && yays == 0 && nays == 0) {
            revert ToucanRelay.CannotVoteZero({
                executionChainId: _executionChainId,
                proposalId: _proposalId,
                voter: msg.sender
            });
        }

        // check that the user can actually vote given their voting power and the proposal
        if (!canVote(_proposalId, msg.sender, _voteOptions)) {
            revert CannotVote({
                executionChainId: _executionChainId,
                proposalId: _proposalId,
                voter: msg.sender,
                voteOptions: _voteOptions
            });
        }

        // get the proposal data
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
        Tally storage lastVote = proposal.voters[msg.sender];

        // revert the last vote
        proposal.tally.abstain -= lastVote.abstain;
        proposal.tally.yes -= lastVote.yes;
        proposal.tally.no -= lastVote.no;

        // update the last vote
        lastVote.abstain = abstentions;
        lastVote.yes = yays;
        lastVote.no = nays;

        // update the total vote
        proposal.tally.abstain += abstentions;
        proposal.tally.yes += yays;
        proposal.tally.no += nays;

        emit VoteCast({
            executionChainId: _executionChainId,
            proposalId: _proposalId,
            voter: msg.sender,
            voteOptions: _voteOptions
        });
    }

    /// @notice This function will take the votes for a given proposal ID and dispatch them to the execution chain.
    /// @param _executionChainId The chain ID where the proposal will be executed.
    /// @param _proposalId The proposal ID to dispatch the votes for.
    /// @param _params Additional parameters required to send the message cross chain.
    /// @dev _params can be constructed using the `quote` function or defined manually.
    /// @dev This is a payable function. The msg.value should be set to the fee.
    function dispatchVotes(
        uint _executionChainId,
        uint256 _proposalId,
        LzSendParams memory _params
    ) external payable noReentrant {
        // get the proposal data and slice the timestamps
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        // check the timestamp
        if (block.timestamp <= startTimestamp) {
            revert ProposalNotOpen({
                executionChainId: _executionChainId,
                proposalId: _proposalId,
                openAt: startTimestamp
            });
        }

        if (block.timestamp > endTimestamp) {
            revert ProposalAlreadyClosed({
                executionChainId: _executionChainId,
                proposalId: _proposalId,
                closedAt: endTimestamp
            });
        }

        // check the proposal has some data
        if (proposal.tally.abstain == 0 && proposal.tally.yes == 0 && proposal.tally.no == 0) {
            revert NoVotesToDispatch({
                executionChainId: _executionChainId,
                proposalId: _proposalId
            });
        }

        bytes memory message = abi.encode(
            ToucanVoteMessage({
                votingChainId: _chainId(),
                proposalId: _proposalId,
                votes: proposal.tally
            })
        );

        // refund should be somewhere safe on the dst chain
        address refund = refundAddress(_params.dstEid);

        // dispatch the votes via the lz endpoint
        _lzSend(_params.dstEid, message, _params.options, _params.fee, refund);

        emit VotesDispatched({
            executionChainId: _executionChainId,
            proposalId: _proposalId,
            votes: proposal.tally
        });
    }

    /// -------- VIEW FUNCTIONS --------

    /// @notice Checks if a voter can vote on a proposal.
    /// @param _proposalId The proposal ID to check, will be decoded to get the start and end timestamps.
    /// @param _voter The address of the voter to check.
    /// @param _voteOptions The vote options to check against the voter's voting power.
    function canVote(
        uint256 _proposalId,
        address _voter,
        Tally memory _voteOptions
    ) public view returns (bool) {
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen({_startTs: startTimestamp, _endTs: endTimestamp})) {
            return false;
        }

        // this could re-enter with a malicious governance token
        uint votingPower = token.getPastVotes(_voter, startTimestamp);

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

    /// @return Vote data for a given execution chain, proposal and voter.
    /// @dev Required due to nested mappings in the proposal struct.
    function getVotes(
        uint256 _executionChainId,
        uint256 _proposalId,
        address _voter
    ) external view returns (Tally memory) {
        return proposals[_executionChainId][_proposalId].voters[_voter];
    }

    /// @dev Checks the timestamps passed by destructuring the proposal ID to see if the proposal is open.
    /// Note that we do not have any information in this implementation that validates if the proposal has already
    /// been executed. This remains the responsibility of the DAO and User.
    function _isProposalOpen(uint32 _startTs, uint32 _endTs) internal view virtual returns (bool) {
        // overflow check seems redundant but L2s sometimes have unique rules and edge cases
        uint32 currentTime = block.timestamp.toUint32();

        // TODO: ERC20 votes requires > _startTs - I think this is different to the block but need to check
        return _startTs < currentTime && currentTime < _endTs;
    }

    /// @return The sums of the votes in a Voting Tally.
    /// @dev Can revert if combined weights exceed the max 256 bit integer.
    function _totalVoteWeight(Tally memory _voteOptions) internal pure virtual returns (uint256) {
        return _voteOptions.yes + _voteOptions.no + _voteOptions.abstain;
    }

    /// @notice Quotes the total gas fee to dispatch the votes cross chain.
    /// @param _executionChainId The EVM chain ID of the destination chain.
    /// @param _proposalId Proposal ID of a current proposal. Is used to fetch vote data.
    /// @param _dstEid LayerZero Endpoint ID for the execution chain.
    /// @param _gasLimit Total additional gas required for operations on the execution chain.
    /// @dev Refunds will be sent to the refundAddress on the execution chain.
    /// @return params The additional parameters required to be sent with the cross chain message.
    /// @dev These can be manually constructed but the defaults provided save some boilerplate.
    function quote(
        uint _executionChainId,
        uint256 _proposalId,
        uint32 _dstEid,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        Proposal storage proposal = proposals[_executionChainId][_proposalId];
        bytes memory message = abi.encode(
            ToucanVoteMessage({
                votingChainId: _chainId(),
                proposalId: _proposalId,
                votes: proposal.tally
            })
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption({
            _gas: _gasLimit,
            _value: 0
        });
        MessagingFee memory fee = _quote({
            _dstEid: _dstEid,
            _message: message,
            _options: options,
            _payInLzToken: false
        });
        return LzSendParams({dstEid: _dstEid, gasLimit: _gasLimit, fee: fee, options: options});
    }

    /// @notice The chain ID of the current chain, by default this returns block.chainid.
    /// @dev This can be overriden if chains have custom logic for determining the chain ID.
    function _chainId() internal view virtual returns (uint256) {
        return block.chainid;
    }

    /// @notice The refund address will receive extra gas on the destination chain.
    /// @param _dstEid The layerZero endpoint ID of the destination chain.
    /// @dev Encoded as a 256bit integer in case we want to change the implementation to a different chain Id.
    /// @return The address that will receive the refund. By default this is the LayerZero peer address.
    ///         which should implement a sweep function to recover the funds.
    function refundAddress(uint256 _dstEid) public view virtual returns (address) {
        return bytes32ToAddress(peers[_dstEid.toUint32()]);
    }

    /// -------- LAYER ZERO RECEIVE --------

    /// @notice Implemented as part of the OApp specifcation, however the relayer cannot receive messages.
    /// @dev This is implemented in the case of upgrades that may require the relayer to receive messages.
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal pure override {
        revert CannotReceive();
    }
}
