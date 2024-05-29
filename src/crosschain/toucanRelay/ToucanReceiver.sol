// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

import {IMajorityVotingV2, IMajorityVoting} from "@interfaces/IMajorityVoting.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanRelayMessage} from "src/crosschain/toucanRelay/ToucanRelay.sol";

import {OApp} from "@lz-oapp/OApp.sol";
import {Plugin} from "@aragon/osx-commons-contracts/src/plugin/Plugin.sol";

import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import {TallyMath} from "@libs/TallyMath.sol";
import {Sweeper} from "src/crosschain/Sweeper.sol";

import "forge-std/console2.sol";

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
        bytes reason
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
contract ToucanReceiver is OApp, IVoteContainer, IToucanReceiverEvents, Plugin, Sweeper {
    using TallyMath for Tally;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- STATE ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice All votes across all chains for a proposal.
    /// @param votesByChain The votes aggregated by each voting chain.
    /// @param aggregateVotes The total votes across all chains.
    struct AggregateTally {
        mapping(uint256 chainId => Tally) votesByChain;
        Tally aggregateVotes;
    }

    /// @dev TODO: OApp implements Ownable so has a different permission system
    bytes32 public constant RECEIVER_ADMIN_ID = keccak256("RECEIVER_ADMIN");

    /// @notice The address of the governance token. Must implement IVotes for vote delegation.
    IVotes public governanceToken;

    /// @notice The address of the voting plugin. Must implement a vote function.
    IMajorityVotingV2 public votingPlugin;

    /// @notice Stores all votes for a proposal across all chains and in aggregate.
    mapping(uint256 proposalId => AggregateTally) public votes;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- ERRORS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Thrown if one of the sliced elements of the proposal ID invalidates the ID.
    error InvalidProposalId(uint256 proposalId);

    /// @notice Thrown if trying to submit votes to the plugin but there are no votes.
    error NoVotesToSubmit(uint256 proposalId);

    /// @notice Thrown if the receiver cannot receive votes for a proposal and thus cannot adjust the vote.
    error CannotReceiveVotes(uint256 votingChainId, uint256 proposalId, Tally votes);

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- CONSTRUCTOR ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @param _governanceToken The address of the governance token, must implement IVotes.
    /// @param _lzEndpoint The address of the Layer Zero endpoint.
    /// @param _dao The address of the Aragon DAO.
    /// @param _votingPlugin The address of the voting plugin. Must implement IMajorityVotingV2.
    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) OApp(_lzEndpoint, _dao) Plugin(IDAO(_dao)) {
        governanceToken = IVotes(_governanceToken);
        _setVotingPlugin(_votingPlugin);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- ADMIN FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Updates the voting plugin in the case of a new voting plugin being released.
    /// @param _plugin The address of the new voting plugin.
    function setVotingPlugin(address _plugin) public auth(RECEIVER_ADMIN_ID) {
        _setVotingPlugin(_plugin);
    }

    /// @dev Internal function to set the voting plugin, called by the public function and the constructor.
    function _setVotingPlugin(address _plugin) internal {
        votingPlugin = IMajorityVotingV2(_plugin);
        emit NewVotingPluginSet(_plugin, msg.sender);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- PUBLIC FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Takes the stored votes for a proposal and sends them to the voting plugin.
    /// @param _proposalId The ID of the proposal. This should be fetched from the plugin.
    /// @dev This function is called by the ToucanRelay after all votes have been received.
    /// It can alternatively be called by anyone in the event that the relay runs out of gas but has stored the votes.
    function submitVotes(uint256 _proposalId) public {
        if (!isProposalIdValid(_proposalId)) revert InvalidProposalId(_proposalId);

        // get the current aggregate votes
        Tally memory aggregate = votes[_proposalId].aggregateVotes;

        // if there are no votes, we don't call the plugin
        if (aggregate.isZero()) revert NoVotesToSubmit(_proposalId);

        // send the votes to the plugin
        // We don't need to run further checks here because the plugin will check the proposal
        // data and the aggregate votes and we are not updating the state.
        votingPlugin.vote(_proposalId, aggregate, false);

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
        // TODO: make sure you test for this though

        // deserialize inbound data
        IToucanRelayMessage.ToucanVoteMessage memory decoded = abi.decode(
            _message,
            (IToucanRelayMessage.ToucanVoteMessage)
        );

        uint256 votingChainId = decoded.votingChainId;
        uint256 proposalId = decoded.proposalId;
        Tally memory receivedVotes = decoded.votes;

        // check if the votes are valid and we can receive them
        if (!canReceiveVotes(proposalId, receivedVotes)) {
            revert CannotReceiveVotes({
                votingChainId: votingChainId,
                proposalId: proposalId,
                votes: receivedVotes
            });
        }

        // update our local state
        _receiveVotes(votingChainId, proposalId, receivedVotes);

        // attempt to submit to the plugin
        // If this fails, the votes are still stored and resubmit attempts can be made.
        try this.submitVotes(proposalId) {} catch (bytes memory reason) {
            emit SubmitVoteFailed({
                proposalId: proposalId,
                votingChainId: votingChainId,
                votes: receivedVotes,
                reason: reason
            });
        }
    }

    /// @dev Internal function to receive votes from the ToucanRelay and update the local state.
    /// @param _votingChainId The EVM ChainID of the voting chain.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @param _votes The votes from the voting chain to be added to the proposal.
    function _receiveVotes(
        uint256 _votingChainId,
        uint256 _proposalId,
        Tally memory _votes
    ) internal {
        AggregateTally storage proposalData = votes[_proposalId];
        Tally storage chainVotes = proposalData.votesByChain[_votingChainId];

        /// remove the existing vote from the aggregate
        proposalData.aggregateVotes = proposalData.aggregateVotes.sub(chainVotes);

        /// add the new vote to the aggregate
        proposalData.aggregateVotes = proposalData.aggregateVotes.add(chainVotes);

        /// update the chain vote
        chainVotes.abstain = _votes.abstain;
        chainVotes.yes = _votes.yes;
        chainVotes.no = _votes.no;

        emit VotesReceived({proposalId: _proposalId, votingChainId: _votingChainId, votes: _votes});
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- VIEW FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Checks if a quanity of votes can be received by a proposal.
    /// @dev Will check the proposal Id for validity then also check the voting power delegated to this contract.
    /// @param _proposalId The ID of the proposal to check against.
    /// @param _votes The votes to add to the proposal.
    function canReceiveVotes(uint256 _proposalId, Tally memory _votes) public view returns (bool) {
        if (!isProposalIdValid(_proposalId)) return false;
        else if (!hasEnoughVotingPowerForNewVotes(_proposalId, _votes)) return false;
        else return true;
    }

    /// @notice Checks if a proposal ID is valid for this contract. Does not check if the proposal exists.
    /// @param _proposalId The ID of the proposal to check. Should be fetched from the voting plugin.
    /// @dev Will check the plugin is the voting plugin and the timestamps are valid.
    function isProposalIdValid(uint256 _proposalId) public view returns (bool) {
        (address plugin, uint32 startTimestamp, uint32 endTimestamp, ) = ProposalIdCodec.decode(
            _proposalId
        );

        if (plugin != address(votingPlugin)) return false;
        // TODO: ensure consistency with the voting plugin and toucan relay for strict equality checks
        else if (block.timestamp <= startTimestamp) return false;
        else if (block.timestamp >= endTimestamp) return false;
        else return true;
    }

    /// @notice Checks if this contract has had enough voting power delegated to accommodate the new votes.
    /// @param _proposalId The ID of the proposal.
    /// @param _votes The voting power to add to the current total.
    /// @dev We fetch the voting power using the block snapshot directly from the voting plugin.
    /// If we receive more votes than we have delegated, something is wrong.
    /// In theory, this should not happen: new tokens can only be minted after
    /// locking tokens in the bridge. However, in the relay, anyone can vote on a proposal id
    /// provided the timestamp is valid. So this function is an extra defense.
    function hasEnoughVotingPowerForNewVotes(
        uint256 _proposalId,
        Tally memory _votes
    ) public view virtual returns (bool) {
        uint256 snapshotBlock = getProposalBlockSnapshot(_proposalId);

        // this proposal does not exist
        // TODO: should this be false? or should we revert? Or just allow it?
        if (snapshotBlock == 0) return false;

        // check if adding the new votes will exceed the voting power when the snapshot was taken
        uint256 votingPowerAtStart = governanceToken.getPastVotes(address(this), snapshotBlock);
        Tally memory currentAggregate = votes[_proposalId].aggregateVotes;

        uint256 additionalVotes = _votes.sum();
        uint256 currentVotes = currentAggregate.sum();

        if (currentVotes + additionalVotes > votingPowerAtStart) return false;
        else return true;
    }

    /// @notice Fetches the last known votes for a proposal on a specific voting chain.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @param _votingChainId The EVM ChainID of the voting chain.
    /// @dev This requires that the votes have been received and stored, and may not be up to date.
    function getVotesByChain(
        uint256 _votingChainId,
        uint256 _proposalId
    ) public view returns (Tally memory) {
        return votes[_proposalId].votesByChain[_votingChainId];
    }

    /// @notice Fetches the latest aggregate votes for a proposal across all voting chains.
    /// @param _proposalId The ID of the proposal from the execution chain.
    /// @dev This requires that the votes have been received and stored, and may not be up to date.
    function getAggregateVotes(uint256 _proposalId) public view returns (Tally memory) {
        return votes[_proposalId].aggregateVotes;
    }

    /// @notice Get the snapshot block for a proposal from the voting plugin.
    /// @return The snapshot block number or 0 if the proposal does not exist.
    function getProposalBlockSnapshot(uint256 _proposalId) public view virtual returns (uint256) {
        (, , IMajorityVoting.ProposalParameters memory params, , , ) = votingPlugin.getProposal(
            _proposalId
        );
        return params.snapshotBlock;
    }
}
