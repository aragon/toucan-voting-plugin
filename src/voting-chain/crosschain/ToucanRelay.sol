// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanRelayMessage} from "@interfaces/IToucanRelayMessage.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {OAppUpgradeable} from "@oapp-upgradeable/aragon-oapp/OAppUpgradeable.sol";
import {ProposalReference, ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import {TallyMath} from "@libs/TallyMath.sol";
import "@utils/converters.sol";

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
/// 2. We can dispatch the votes to a single execution chain
/// 3. User can change their vote (if the proposal has not ended)
/// 4. We can split a user's vote across y/n/a
/// 5. Users can partial vote
contract ToucanRelay is
    IVoteContainer,
    IToucanRelayMessage,
    ReentrancyGuardUpgradeable,
    OAppUpgradeable,
    PluginUUPSUpgradeable
{
    using OptionsBuilder for bytes;
    using ProposalRefEncoder for uint256;
    using TallyMath for Tally;
    using SafeCast for uint256;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- STATE ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Subset of proposal data seen required to dispatch votes cross chain.
    /// @param tally Aggregated votes for the proposal.
    /// @param voters Mapping of voters to their most recent vote choices.
    /// @dev voter => lastVote
    struct Proposal {
        Tally tally;
        mapping(address => Tally) voters;
    }

    /// @notice Additional Layer Zero params required to send a cross chain message.
    /// @param gasLimit The additional gas needed on the execution chain to process the message, surplus will be refunded.
    /// @param fee The messaging fee required to send the message, this is sent to LayerZero.
    /// @param options Additional options required to send the message, these are encoded as bytes.
    struct LzSendParams {
        uint128 gasLimit;
        MessagingFee fee;
        bytes options;
    }

    /// @notice The voting token used by the relay. Must use a timestamp based clock on the voting chain.
    IVotes public token;

    /// @notice The layer zero destination EID currently set for the relay.
    /// @dev This will be the chain that the votes are recorded against, and dispatched to.
    uint32 public dstEid;

    /// @notice The buffer in seconds before a proposal closes that votes can no longer be cast.
    /// @dev This is to allow for delays in cross chain communication that would prevent votes being cast
    /// that do not have time to be bridged.
    /// @dev The admin can set it to 0 to disable the buffer.
    uint32 public buffer;

    /// @notice The proposals are stored in a nested mapping by eid and proposal reference.
    /// @dev This relies on a critical assumption of a single execution chain.
    /// @dev dstEid => proposalRef => Proposal
    mapping(uint32 => mapping(uint256 => Proposal)) internal _proposals;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- ERRORS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Enumerable error codes to avoid reverting view functions but still provide context.
    /// @param None No error occurred.
    /// @param ProposalNotOpen The proposal is not open for voting.
    /// @param ZeroVotes The user is trying to vote with zero votes.
    /// @param InsufficientVotingPower The user has insufficient voting power to vote.
    /// @param NotEnoughTimeToBridge The proposal does not have enough time remaining to bridge the votes.
    enum ErrReason {
        None,
        ZeroVotes,
        ProposalNotOpen,
        InsufficientVotingPower,
        NotEnoughTimeToBridge
    }

    /// @notice Thrown if the voter fails the `canVote` check during the voting process.
    error CannotVote(uint256 proposalRef, address voter, Tally voteOptions, ErrReason reason);

    /// @notice Thrown if the votes cannot be dispatched according to `canDispatch`.
    error CannotDispatch(uint256 proposalRef, ErrReason reason);

    /// @notice Thrown if this OAapp cannot receive messages.
    error CannotReceive();

    /// @notice Thrown if the token address is zero.
    error InvalidToken();

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- EVENTS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Emitted when a voter successfully casts a vote on a proposal.
    event VoteCast(uint32 dstEid, uint256 indexed proposalRef, address voter, Tally voteOptions);

    /// @notice Emitted when anyone dispatches the votes for a proposal to the execution chain.
    event VotesDispatched(uint32 dstEid, uint256 indexed proposalRef, Tally votes);

    /// @notice Emitted when the destination EID is updated.
    event DestinationEidUpdated(uint32 dstEid);

    /// @notice Emitted when the bridge delay buffer is updated.
    event BrigeDelayBufferUpdated(uint32 buffer);

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- INITIALIZER ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    constructor() {
        _disableInitializers();
    }

    /// @param _token The voting token used by the relay. Should be a timestamp based voting token.
    /// @param _lzEndpoint The LayerZero endpoint address for the relay on this chain.
    /// @param _dao The DAO address that will be the owner of this relay and will control permissions.
    function initialize(
        address _token,
        address _lzEndpoint,
        address _dao,
        uint32 _dstEid,
        uint32 _buffer
    ) external initializer {
        __OApp_init(_lzEndpoint, _dao);
        // don't call plugin init as this would re-initilize.
        if (_token == address(0)) revert InvalidToken();
        token = IVotes(_token);
        _setDstEid(_dstEid);
        _setBridgeDelayBuffer(_buffer);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- STATE MODIFYING FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Sets the destination chain ID for the relay.
    /// @dev Once set, votes will be held against and dispatched to this chain.
    function setDstEid(uint32 _dstEid) external auth(OAPP_ADMINISTRATOR_ID) {
        _setDstEid(_dstEid);
    }

    /// @dev Internal function to set the destination chain ID and emit an event.
    function _setDstEid(uint32 _dstEid) internal {
        dstEid = _dstEid;
        emit DestinationEidUpdated(_dstEid);
    }

    /// @notice Sets the bridge delay for the relay. This is a window before the proposal officially
    /// closes where votes can no longer be cast. This is to allow for cross chain communication.
    /// @param _buffer The delay in seconds.
    function setBridgeDelayBuffer(uint32 _buffer) external auth(OAPP_ADMINISTRATOR_ID) {
        _setBridgeDelayBuffer(_buffer);
    }

    function _setBridgeDelayBuffer(uint32 _buffer) internal {
        buffer = _buffer;
        emit BrigeDelayBufferUpdated(_buffer);
    }

    /// @notice Anyone with a voting token that has voting power can vote on a proposal.
    /// @param _proposalRef The proposal reference to vote on.
    /// @dev Must be computed from execution chain proposal params as it is not validated here.
    /// @param _voteOptions Votes split between yes no and abstain up to the voter's total voting power.
    function vote(uint256 _proposalRef, Tally calldata _voteOptions) external nonReentrant {
        // check that the user can actually vote given their voting power and the proposal
        (bool success, ErrReason e) = canVote(_proposalRef, msg.sender, _voteOptions);
        if (!success) revert CannotVote(_proposalRef, msg.sender, _voteOptions, e);

        // get the proposal data
        Proposal storage proposal = _proposals[dstEid][_proposalRef];
        Tally storage lastVote = proposal.voters[msg.sender];

        // revert the last vote, doesn't matter if user hasn't voted before
        proposal.tally = proposal.tally.sub(lastVote);

        // update the total vote
        proposal.tally = proposal.tally.add(_voteOptions);

        // update the last vote
        // we have to set by item due to no implicit storage casting
        lastVote.abstain = _voteOptions.abstain;
        lastVote.yes = _voteOptions.yes;
        lastVote.no = _voteOptions.no;

        emit VoteCast(dstEid, _proposalRef, msg.sender, _voteOptions);
    }

    /// @notice This function will take the votes for a given proposal ID and dispatch them to the execution chain.
    /// @param _proposalRef The proposal reference to dispatch the votes for.
    /// @param _params Additional parameters required to send the message cross chain.
    /// @dev _params can be constructed using the `quote` function or defined manually.
    /// @dev This is a payable function. The msg.value should be set to the fee.
    function dispatchVotes(
        uint256 _proposalRef,
        LzSendParams memory _params
    ) external payable nonReentrant {
        // check if we can dispatch the votes
        (bool success, ErrReason e) = canDispatch(_proposalRef);
        if (!success) revert CannotDispatch(_proposalRef, e);

        // get the votes and encode the message
        Tally memory proposalVotes = _proposals[dstEid][_proposalRef].tally;
        bytes memory message = abi.encode(
            ToucanVoteMessage({
                votingChainId: _chainId(),
                proposalRef: _proposalRef,
                votes: proposalVotes
            })
        );

        // refund should be somewhere safe on the dst chain
        address refund = refundAddress(dstEid);

        // dispatch the votes via the lz endpoint
        _lzSend(dstEid, message, _params.options, _params.fee, refund);

        emit VotesDispatched(dstEid, _proposalRef, proposalVotes);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- VIEW FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Quotes the total gas fee to dispatch the votes cross chain.
    /// @param _proposalRef Proposal reference of a current proposal. Is used to fetch vote data.
    /// @param _gasLimit Total additional gas required for operations on the execution chain.
    /// @dev Refunds will be sent to the refundAddress on the execution chain.
    /// @return params The additional parameters required to be sent with the cross chain message.
    /// @dev These can be manually constructed but the defaults provided save some boilerplate.
    function quote(
        uint256 _proposalRef,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        Proposal storage proposal = _proposals[dstEid][_proposalRef];
        bytes memory message = abi.encode(
            ToucanVoteMessage({
                votingChainId: _chainId(),
                proposalRef: _proposalRef,
                votes: proposal.tally
            })
        );
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption({
            _gas: _gasLimit,
            _value: 0
        });
        MessagingFee memory fee = _quote({
            _dstEid: dstEid,
            _message: message,
            _options: options,
            _payInLzToken: false
        });
        return LzSendParams(_gasLimit, fee, options);
    }

    /// @notice Checks if a voter can vote on a proposal.
    /// @param _proposalRef The proposal reference to check, will be decoded to get timestamps for start end and block.
    /// @param _voter The address of the voter to check.
    /// @param _voteOptions The vote options to check against the voter's voting power.
    function canVote(
        uint256 _proposalRef,
        address _voter,
        Tally memory _voteOptions
    ) public view returns (bool, ErrReason) {
        // the user is trying to vote with zero votes
        if (_voteOptions.isZero()) return (false, ErrReason.ZeroVotes);

        // Check the proposal is open as defined by the timestamps in the proposal ID
        if (!isProposalOpen(_proposalRef)) return (false, ErrReason.ProposalNotOpen);

        // Check if the proposal has enough time to bridge
        if (!hasEnoughTimeToBridge(_proposalRef)) return (false, ErrReason.NotEnoughTimeToBridge);

        // this could re-enter with a malicious governance token
        uint256 votingPower = token.getPastVotes(_voter, _proposalRef.getBlockSnapshotTimestamp());

        // the user has insufficient voting power to vote
        if (_totalVoteWeight(_voteOptions) > votingPower)
            return (false, ErrReason.InsufficientVotingPower);

        // At the moment, we always allow vote replacement. This could be changed in the future.
        return (true, ErrReason.None);
    }

    /// @notice Checks if a proposal has enough time to bridge votes.
    function hasEnoughTimeToBridge(uint256 _proposalRef) public view returns (bool) {
        if (buffer == 0) return true;

        // get the end time of the proposal
        uint32 endTs = _proposalRef.getEndTimestamp();

        // get the current time
        uint256 currentTime = block.timestamp;

        // check if the proposal has enough time to bridge
        // cast buffer to uint256 to avoid overflow from addition
        return currentTime + uint256(buffer) < endTs;
    }

    /// @notice Checks if the votes for a proposal can be dispatched cross chain.
    /// @param _proposalRef The proposal reference to check.
    /// @return Whether a proposal is open and has votes to dispatch.
    function canDispatch(uint256 _proposalRef) public view virtual returns (bool, ErrReason) {
        // Check the proposal is open as defined by the timestamps in the proposal ID
        if (!isProposalOpen(_proposalRef)) return (false, ErrReason.ProposalNotOpen);

        // check that there are votes to dispatch
        Tally memory proposalVotes = _proposals[dstEid][_proposalRef].tally;
        if (proposalVotes.isZero()) return (false, ErrReason.ZeroVotes);

        return (true, ErrReason.None);
    }

    /// @return If a proposal is accepting votes, as defined by the timestamps in the proposal reference.
    /// Note that we do not have any information in this implementation that validates if the proposal has already
    /// been executed. This remains the responsibility of the DAO and User.
    function isProposalOpen(uint256 _proposalRef) public view virtual returns (bool) {
        // overflow check seems redundant but L2s sometimes have unique rules and edge cases
        uint32 currentTime = block.timestamp.toUint32();
        return _proposalRef.isOpen(currentTime);
    }

    /// @return The sums of the votes in a Voting Tally.
    /// @dev Can revert if combined weights exceed the max 256 bit integer.
    function _totalVoteWeight(Tally memory _voteOptions) internal pure virtual returns (uint256) {
        return _voteOptions.sum();
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

    /// @return Vote data for a given proposal, voter and chain.
    /// @dev Required due to nested mappings in the proposal struct.
    function getVotes(
        uint32 _dstEid,
        uint256 _proposalRef,
        address _voter
    ) external view returns (Tally memory) {
        return _proposals[_dstEid][_proposalRef].voters[_voter];
    }

    /// @return Vote data for a given proposal and voter, for the currently set destination chain.
    function getVotes(uint256 _proposalRef, address _voter) external view returns (Tally memory) {
        return _proposals[dstEid][_proposalRef].voters[_voter];
    }

    /// @notice External getter to fetch proposal votes.
    /// @param _proposalRef The proposal reference to get the votes for.
    /// @return The tally of votes for a given proposal and the current EID.
    function proposals(uint256 _proposalRef) external view returns (Tally memory) {
        return proposals(dstEid, _proposalRef);
    }

    /// @notice External getter to fetch proposal votes for a passed EID.
    /// @param _dstEid The destination EID to get the proposal data for.
    /// @param _proposalRef The proposal reference to get the votes for.
    /// @return The tally of votes for a given proposal and EID.
    function proposals(uint32 _dstEid, uint256 _proposalRef) public view returns (Tally memory) {
        return _proposals[_dstEid][_proposalRef].tally;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- LAYER ZERO RECEIVE --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- UPGRADE FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @dev Keeps permissions lean by giving OApp administrator the ability to upgrade.
    /// The alternative would be to define a separate permission which adds complexity.
    /// As this contract is upgradeable, this can be changed in the future.
    function _authorizeUpgrade(address) internal override auth(OAPP_ADMINISTRATOR_ID) {}

    /// @dev Gap to reserve space for future storage layout changes.
    uint256[46] private __gap;
}
