// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";

interface IVoteContainer {
    /// @notice A container for the proposal vote tally.
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }
}

/// @title IToucanVoting
/// @author Aragon X - 2024
/// @notice Interface for Aragon IVotes-based voting and proposal plugin "ToucanVoting".
/// @custom:security-contact sirt@aragon.org
interface IToucanVoting is IVoteContainer {
    /// @notice The different voting modes available.
    /// @param Standard In standard mode, early execution and vote replacement are disabled.
    /// @param EarlyExecution In early execution mode, a proposal can be executed
    /// early before the end date if the vote outcome cannot mathematically change by more voters voting.
    /// @param VoteReplacement In vote replacement mode, voters can change their vote
    /// multiple times and only the latest vote option is tallied.
    enum VotingMode {
        Standard,
        EarlyExecution,
        VoteReplacement
    }

    /// @notice A container for the majority voting settings that will be applied as parameters on proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// In standard mode (0), early execution and vote replacement are disabled.
    /// In early execution mode (1), a proposal can be executed early before the end date
    /// if the vote outcome cannot mathematically change by more voters voting.
    /// In vote replacement mode (2), voters can change their vote multiple times
    /// and only the latest vote option is tallied.
    /// @param supportThreshold The support threshold value.
    /// Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minParticipation The minimum participation value.
    /// Its value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    struct VotingSettings {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint32 minParticipation;
        uint32 minDuration;
        uint256 minProposerVotingPower;
    }

    /// @notice A container for proposal-related information.
    /// @param executed Whether the proposal is executed or not.
    /// @param parameters The proposal parameters at the time of the proposal creation.
    /// @param tally The vote tally of the proposal.
    /// @param voters The votes casted by the voters. In the case of replacement will be the most recent votes.
    /// @param actions The actions to be executed when the proposal passes.
    /// @param allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert.
    /// If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts.
    /// A failure map value of 0 requires every action to not revert.
    struct Proposal {
        bool executed;
        ProposalParameters parameters;
        Tally tally;
        mapping(address => Tally) voters;
        IDAO.Action[] actions;
        uint256 allowFailureMap;
    }

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    /// The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param snapshotTimestamp The timestamp of the block prior to the proposal creation.
    /// @param minVotingPower The minimum voting power needed.
    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint32 startDate;
        uint32 endDate;
        uint32 snapshotBlock;
        uint32 snapshotTimestamp;
        uint256 minVotingPower;
    }

    /// @notice A container for the snapshot block when the proposal was created.
    /// @param number The block number before the proposal creation.
    /// @param timestamp The block timestamp before the proposal creation.
    struct SnapshotBlock {
        uint32 number;
        uint32 timestamp;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- SETTERS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Creates a new majority voting proposal.
    /// @param _metadata The metadata of the proposal.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @param _allowFailureMap Allows proposal to succeed even if an action reverts.
    /// Uses bitmap representation.
    /// If the bit at index `x` is 1, the tx succeeds even if the action at `x` failed.
    /// Passing 0 will be treated as atomic execution.
    /// @param _startDate The start date of the proposal vote.
    /// If 0, the current timestamp is used and the vote starts immediately.
    /// @param _endDate The end date of the proposal vote.
    /// If 0, `_startDate + minDuration` is used.
    /// @param _votes The chosen votes to be casted on proposal creation.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    /// The call does not revert if early execution is not possible.
    /// @return proposalId The ID of the proposal.
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint32 _startDate,
        uint32 _endDate,
        Tally memory _votes,
        bool _tryEarlyExecution
    ) external returns (uint256 proposalId);

    /// @notice Votes for a vote option and, optionally, executes the proposal.
    /// @dev `_voteOption`, 1 -> abstain, 2 -> yes, 3 -> no
    /// @param _proposalId The ID of the proposal.
    /// @param _votes The chosen vote option.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    /// The call does not revert if early execution is not possible.
    function vote(uint256 _proposalId, Tally memory _votes, bool _tryEarlyExecution) external;

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    /// @notice Updates the voting settings.
    /// @param _votingSettings The new voting settings.
    function updateVotingSettings(VotingSettings calldata _votingSettings) external;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- GETTERS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice getter function for the voting token.
    /// @dev external function also useful for registering interfaceId
    /// and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function getVotingToken() external view returns (IVotesUpgradeable);

    /// @notice Returns whether the account has voted for the proposal.
    /// Note, that this does not check if the account has voting power.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return votes cast by a voter for a certain proposal.
    function getVotes(
        uint256 _proposalId,
        address _account
    ) external view returns (Tally memory votes);

    /// @notice Returns all information for a proposal vote by its ID.
    /// @param _proposalId The ID of the proposal.
    /// @return open Whether the proposal is open or not.
    /// @return executed Whether the proposal is executed or not.
    /// @return parameters The parameters of the proposal vote.
    /// @return tally The current tally of the proposal vote.
    /// @return actions The actions to be executed in the associated DAO after the proposal has passed.
    /// @return allowFailureMap The bit map representations of which actions are allowed to revert so tx still succeeds.
    function getProposal(
        uint256 _proposalId
    )
        external
        view
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            Tally memory tally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        );

    /// @notice Returns the total voting power checkpointed for a specific block number.
    /// @param _blockNumber The block number.
    /// @return The total voting power.
    function totalVotingPower(uint256 _blockNumber) external view returns (uint256);

    /// @notice Returns the support threshold parameter stored in the voting settings.
    /// @return The support threshold parameter.
    function supportThreshold() external view returns (uint32);

    /// @notice Returns the minimum participation parameter stored in the voting settings.
    /// @return The minimum participation parameter.
    function minParticipation() external view returns (uint32);

    /// @notice Returns the minimum duration parameter stored in the voting settings.
    /// @return The minimum duration parameter.
    function minDuration() external view returns (uint32);

    /// @notice Returns the minimum voting power required to create a proposal stored in the voting settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() external view returns (uint256);

    /// @notice Returns the vote mode stored in the voting settings.
    /// @return The vote mode parameter.
    function votingMode() external view returns (VotingMode);

    /// @notice Checks if the support value defined as:
    /// $$\texttt{support} = \frac{N_\text{yes}}{N_\text{yes}+N_\text{no}}$$
    /// for a proposal vote is greater than the support threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the  support is greater than the support threshold and `false` otherwise.
    function isSupportThresholdReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the worst-case support value defined as:
    /// $$\texttt{worstCaseSupport} = \frac{N_\text{yes}}{ N_\text{total}-N_\text{abstain}}$$
    /// for a proposal vote is greater than the support threshold.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the worst-case support is greater than the support threshold and `false` otherwise.
    function isSupportThresholdReachedEarly(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the participation value defined as:
    /// $$\texttt{participation} = \frac{N_\text{yes}+N_\text{no}+N_\text{abstain}}{N_\text{total}}$$
    /// for a proposal vote is greater or equal than the minimum participation value.
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the participation is greater than the minimum participation and `false` otherwise.
    function isMinParticipationReached(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if the proposal is open for voting at this time. 
    /// @param _proposalId The ID of the proposal.
    /// @return Returns `true` if the proposal timestamps indicate it's still open and hasn't been executed.
    function isProposalOpen(uint256 _proposalId) external view returns (bool);

    /// @notice Checks if an account can participate on a proposal vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have voting powers.
    /// @param _proposalId The proposal Id.
    /// @param _account The account address to be checked.
    /// @param  _votes Voting allocation to verify against.
    /// @return Returns true if the account is allowed to vote.
    /// @dev The function assumes the queried proposal exists.
    function canVote(
        uint256 _proposalId,
        address _account,
        Tally memory _votes
    ) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);
}
