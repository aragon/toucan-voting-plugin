// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IToucanVoting} from "@toucan-voting/IToucanVoting.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanRelayMessage} from "@interfaces/IToucanRelayMessage.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {OAppUpgradeable} from "@oapp-upgradeable/aragon-oapp/OAppUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";

import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import {TallyMath} from "@libs/TallyMath.sol";
import {SweeperUpgradeable} from "@utils/SweeperUpgradeable.sol";

/// @notice Events emitted by the ToucanReceiver contract.
/// @dev Separation of events makes for easier testing.
interface IToucanReceiverEvents {
    /// @notice Emitted when the voting plugin is updated.
    event NewVotingPluginSet(address plugin, address caller);

    /// @notice Emitted when votes are received from the ToucanRelay and the local state updated.
    /// @dev Does not necessarily mean the votes have been submitted to the voting plugin.
    event VotesReceived(uint256 votingChainId, uint256 proposalId, IVoteContainer.Tally votes);

    /// @notice Emitted when votes are successfully submitted to the voting plugin.
    event SubmitVoteSuccess(uint256 proposalId, address plugin, IVoteContainer.Tally votes);

    /// @notice Emitted when a vote is successfully received from the ToucanRelay but cannot be submitted to the plugin.
    event SubmitVoteFailed(
        uint256 votingChainId,
        uint256 proposalId,
        IVoteContainer.Tally votes,
        bytes revertData
    );
}

/// @title ToucanReceiver
/// @author Aragon
/// @notice Receives votes from the ToucanRelay and aggregates them before sending to the voting plugin.
/// @dev The receiver is delegated all voting power locked in the bridge to other chains.
/// @dev The receiver's security model is dependent on a few key invariants:
/// 1. There is no way to mint tokens on other chains without locking them in the bridge.
/// 2. The relayer correctly validates the voting power on the other chain.
/// @dev Although this contract is an OApp, it does not have any send functionality.
/// This is intentional in the event of future upgrades that may mandate sending cross chain data.
contract ToucanReceiver is
    OAppUpgradeable,
    IVoteContainer,
    IToucanReceiverEvents,
    PluginUUPSUpgradeable,
    SweeperUpgradeable
{
    using TallyMath for Tally;
    using ProposalRefEncoder for uint256;
    using SafeCast for uint256;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- STATE ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice All votes across all chains for a proposal.
    /// @param votesByChain The votes aggregated by each voting chain.
    /// @dev chainId => Tally
    /// @param aggregateVotes The total votes across all chains.
    struct AggregateTally {
        mapping(uint256 => Tally) votesByChain;
        Tally aggregateVotes;
    }

    /// @notice The address of the governance token. Must implement IVotes for vote delegation.
    IVotes public governanceToken;

    /// @notice The address of the voting plugin. Must implement a vote function.
    address public votingPlugin;

    /// @notice Stores all votes for a proposal across all chains and in aggregate.
    /// @dev plugin => proposalId => AggregateTally
    mapping(address => mapping(uint256 => AggregateTally)) internal _votes;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- ERRORS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Error codes to be returned inside view functions to avoid reverting.
    /// @param None No error.
    /// @param ZeroVotes No votes were found for the proposal.
    /// @param InsufficientVotingPower The receiver does not have enough voting power to receive the votes.
    enum ErrReason {
        None,
        ZeroVotes,
        ProposalNotOpen,
        InsufficientVotingPower
    }

    /// @notice Thrown if the receiver cannot receive votes for a proposal and thus cannot adjust the vote.
    error CannotReceiveVotes(
        uint256 votingChainId,
        uint256 proposalId,
        Tally votes,
        ErrReason reason
    );

    /// @notice Thrown if one of the sliced elements of the proposal reference doesn't match the data passed.
    error InvalidProposalReference(uint256 proposalRef);

    /// @notice Thrown if trying to submit votes to the plugin but there are no votes.
    error NoVotesToSubmit(uint256 proposalId);

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- INITIALIZER ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    constructor() {
        _disableInitializers();
    }

    /// @param _governanceToken The address of the governance token, must implement IVotes.
    /// @param _lzEndpoint The address of the Layer Zero endpoint.
    /// @param _dao The address of the Aragon DAO.
    /// @param _votingPlugin The address of the voting plugin. Must implement IMajorityVotingV2.
    function initialize(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) external initializer {
        __OApp_init(_lzEndpoint, _dao);
        // don't call Plugin init as this would reinit daoAuthorizable
        governanceToken = IVotes(_governanceToken);
        _setVotingPlugin(_votingPlugin);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- ADMIN FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Updates the voting plugin in the case of a new voting plugin being released.
    /// @dev Changing the plugin will change how all votes are stored.
    /// @param _plugin The address of the new voting plugin.
    function setVotingPlugin(address _plugin) public auth(OAPP_ADMINISTRATOR_ID) {
        _setVotingPlugin(_plugin);
    }

    /// @dev Internal function to set the voting plugin, called by the public function and the constructor.
    function _setVotingPlugin(address _plugin) internal {
        votingPlugin = _plugin;
        emit NewVotingPluginSet(_plugin, msg.sender);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- PUBLIC FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Takes the stored votes for a proposal and sends them to the voting plugin.
    /// @param _proposalId The ID of the proposal. This should be fetched from the plugin.
    /// @dev This function is called by the ToucanRelay after all votes have been received.
    /// It can alternatively be called by anyone in the event that the relay runs out of gas but has stored the votes.
    function submitVotes(uint256 _proposalId) public virtual {
        // get the current aggregate votes
        Tally memory aggregate = _votes[votingPlugin][_proposalId].aggregateVotes;

        // if there are no votes, we don't call the plugin
        if (aggregate.isZero()) revert NoVotesToSubmit(_proposalId);

        // send the votes to the plugin
        // We don't need to run further checks here because the plugin will check this for us.
        IToucanVoting(votingPlugin).vote(_proposalId, aggregate, false);

        emit SubmitVoteSuccess(_proposalId, address(votingPlugin), aggregate);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- LAYER ZERO RECEIVE --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Internal function to receive data from the endpoint.
    /// @param _message the encoded data from the relay.
    /// @dev Attempts to submit the votes to the voting plugin after receiving them.
    /// If the votes are valid for reciept but there is an error in submitting, the votes are still stored.
    /// We can then attempt to submit them again using the public submitVotes function.
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {
        // OAppReceiver checks the origin to ensure that the sender is the endpoint
        // and the original sender is the peer. So we don't need to check it here.

        // deserialize inbound data
        IToucanRelayMessage.ToucanVoteMessage memory decoded = abi.decode(
            _message,
            (IToucanRelayMessage.ToucanVoteMessage)
        );
        uint256 votingChainId = decoded.votingChainId;
        uint256 proposalRef = decoded.proposalRef;
        Tally memory receivedVotes = decoded.votes;

        // check that the passed proposal ref matches all elements of the proposal params
        if (!isProposalRefValid(proposalRef)) revert InvalidProposalReference(proposalRef);

        // use the proposal id from the reference from here onwards, now we know it's valid
        uint256 proposalId = proposalRef.getProposalId();

        // check if the votes are valid and we can receive them
        (bool success, ErrReason reason) = canReceiveVotes(proposalId, receivedVotes);
        if (!success) {
            revert CannotReceiveVotes({
                votingChainId: votingChainId,
                proposalId: proposalId,
                votes: receivedVotes,
                reason: reason
            });
        }

        // update our local state
        _receiveVotes(votingChainId, proposalId, receivedVotes);

        // attempt to submit to the plugin
        // If this fails (i.e. OOG) the votes are still stored and resubmit attempts can be made.
        try this.submitVotes(proposalId) {} catch (bytes memory revertData) {
            emit SubmitVoteFailed({
                proposalId: proposalId,
                votingChainId: votingChainId,
                votes: receivedVotes,
                revertData: revertData
            });
        }
    }

    /// @dev Internal function to receive votes from the ToucanRelay and update the local state.
    /// @param _votingChainId The EVM ChainID of the voting chain.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @param _tally The votes from the voting chain to be added to the proposal.
    function _receiveVotes(
        uint256 _votingChainId,
        uint256 _proposalId,
        Tally memory _tally
    ) internal {
        AggregateTally storage proposalData = _votes[votingPlugin][_proposalId];
        Tally storage chainVotes = proposalData.votesByChain[_votingChainId];

        /// remove the existing vote from the aggregate
        proposalData.aggregateVotes = proposalData.aggregateVotes.sub(chainVotes);

        /// add the new vote to the aggregate
        proposalData.aggregateVotes = proposalData.aggregateVotes.add(_tally);

        /// update the chain vote
        chainVotes.abstain = _tally.abstain;
        chainVotes.yes = _tally.yes;
        chainVotes.no = _tally.no;

        emit VotesReceived({proposalId: _proposalId, votingChainId: _votingChainId, votes: _tally});
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- VIEW FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Checks if a quanity of votes can be received by a proposal.
    /// @dev Check the proposal is open and that the receiver has enough voting power to make the vote.
    /// @param _proposalId The ID of the proposal to check against.
    /// @param _tally The votes to add to the proposal.
    function canReceiveVotes(
        uint256 _proposalId,
        Tally memory _tally
    ) public view virtual returns (bool, ErrReason) {
        if (_tally.isZero()) {
            return (false, ErrReason.ZeroVotes);
        } else if (!isProposalOpen(_proposalId)) {
            return (false, ErrReason.ProposalNotOpen);
        } else if (!hasEnoughVotingPowerForNewVotes(_proposalId, _tally)) {
            return (false, ErrReason.InsufficientVotingPower);
        } else {
            return (true, ErrReason.None);
        }
    }

    /// @notice Checks if the data encoded in the proposal reference matches the proposal parameters
    /// that are stored in the voting plugin, as indicated by the proposal ID.
    /// @param _proposalRef The encoded proposal reference to validiate.
    function isProposalRefValid(uint256 _proposalRef) public view virtual returns (bool) {
        uint256 _proposalId = _proposalRef.getProposalId();
        return getProposalRef(_proposalId) == _proposalRef;
    }

    /// @notice Checks the voting plugin to see if a proposal is open.
    function isProposalOpen(uint256 _proposalId) public view virtual returns (bool) {
        return IToucanVoting(votingPlugin).isProposalOpen(_proposalId);
    }

    /// @notice Checks if this contract has had enough voting power delegated to accommodate the new votes.
    /// @param _proposalId The ID of the proposal.
    /// @param _tally The voting power to add to the current total.
    /// @dev We fetch the voting power using the block snapshot directly from the voting plugin.
    /// If we receive more votes than we have delegated, something is wrong.
    /// In theory, this should not happen: new tokens can only be minted after
    /// locking tokens in the bridge. However, in the relay, anyone can vote on a proposal id
    /// provided the timestamp is valid. So this function is an extra defense.
    function hasEnoughVotingPowerForNewVotes(
        uint256 _proposalId,
        Tally memory _tally
    ) public view virtual returns (bool) {
        // if no snapshot block exists, we assume the proposal does not exist
        uint256 snapshotBlock = getProposalParams(_proposalId).snapshotBlock;
        if (snapshotBlock == 0) return false;

        // check if adding the new votes will exceed the voting power when the snapshot was taken
        uint256 votingPowerAtStart = governanceToken.getPastVotes(address(this), snapshotBlock);

        // skip further checks if there is no voting power
        if (votingPowerAtStart == 0) return false;

        Tally memory currentAggregate = _votes[votingPlugin][_proposalId].aggregateVotes;

        uint256 additionalVotes = _tally.sum();
        uint256 currentVotes = currentAggregate.sum();

        if (currentVotes + additionalVotes > votingPowerAtStart) return false;
        else return true;
    }

    /// @notice Fetches the total votes for a proposal across all chains.
    /// @param _proposalId The ID of the proposal from the execution chain.
    function votes(uint256 _proposalId) public view returns (Tally memory) {
        return _votes[votingPlugin][_proposalId].aggregateVotes;
    }

    /// @notice Fetches the last known votes for a proposal on a specific voting chain.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @param _votingChainId The EVM ChainID of the voting chain.
    /// @dev This requires that the votes have been received and stored, and may not be up to date.
    function votes(
        uint256 _proposalId,
        uint256 _votingChainId
    ) external view returns (Tally memory) {
        return votes(_proposalId, _votingChainId, votingPlugin);
    }

    /// @notice Fetches the last known votes for a proposal on a specific voting chain and for a specific plugin.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @param _votingChainId The EVM ChainID of the voting chain.
    /// @param _votingPlugin The address of the voting plugin.
    /// @dev This requires that the votes have been received and stored, and may not be up to date.
    function votes(
        uint256 _proposalId,
        uint256 _votingChainId,
        address _votingPlugin
    ) public view returns (Tally memory) {
        return _votes[_votingPlugin][_proposalId].votesByChain[_votingChainId];
    }

    /// @notice Fetches the proposal parameters from the voting plugin.
    function getProposalParams(
        uint256 _proposalId
    ) public view virtual returns (IToucanVoting.ProposalParameters memory) {
        (, , IToucanVoting.ProposalParameters memory params, , , ) = IToucanVoting(votingPlugin)
            .getProposal(_proposalId);

        return params;
    }

    /// @notice Fetches proposal data from the voting plugin and encodes it into a proposal reference.
    /// @dev This reference can be used in cross chain voting in place of bridging the proposal data.
    function getProposalRef(uint256 _proposalId) public view virtual returns (uint256) {
        IToucanVoting.ProposalParameters memory params = getProposalParams(_proposalId);
        return getProposalRef(_proposalId, params);
    }

    /// @notice Uses the proposal parameters to encode a proposal reference.
    function getProposalRef(
        uint256 _proposalId,
        IToucanVoting.ProposalParameters memory _params
    ) public view virtual returns (uint256) {
        return
            ProposalRefEncoder.encode({
                _proposalId: _proposalId.toUint32(),
                _plugin: votingPlugin,
                _proposalStartTimestamp: _params.startDate,
                _proposalEndTimestamp: _params.endDate,
                _proposalBlockSnapshotTimestamp: _params.snapshotBlock
            });
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- UPGRADE FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @dev Keeps permissions lean by giving OApp administrator the ability to upgrade.
    /// The alternative would be to define a separate permission which adds complexity.
    /// As this contract is upgradeable, this can be changed in the future.
    function _authorizeUpgrade(address) internal override auth(OAPP_ADMINISTRATOR_ID) {}

    /// @dev Gap for upgrade storage slots.
    uint256[47] private __gap;
}
