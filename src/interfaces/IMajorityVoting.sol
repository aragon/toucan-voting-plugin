// SPDX-License-Identifier: AGPL-3.0-or-later
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

pragma solidity ^0.8.8;

/// @title IMajorityVoting
/// @author Aragon X - 2022-2023
/// @notice The interface of majority voting plugin.
/// @custom:security-contact sirt@aragon.org
interface IMajorityVoting is IVoteContainer {
    /// @notice Vote options that a voter can chose from.
    /// @dev Voters can now choose to split their votes across multiple options.
    /// @param None The default option state of a voter indicating the absence from the vote.
    /// This option neither influences support nor participation.
    /// @param Abstain This option does not influence the support but counts towards participation.
    /// @param Yes This option increases the support and counts towards participation.
    /// @param No This option decreases the support and counts towards participation.
    /// @param Mixed This option is used to indicate that the voter has split their votes across multiple options.
    enum VoteOption {
        None,
        Abstain,
        Yes,
        No
    }

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

    /// @notice A container for the proposal parameters at the time of proposal creation.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    /// The value has to be in the interval [0, 10^6] defined by `RATIO_BASE = 10**6`.
    /// @param startDate The start date of the proposal vote.
    /// @param endDate The end date of the proposal vote.
    /// @param snapshotBlock The number of the block prior to the proposal creation.
    /// @param minVotingPower The minimum voting power needed.
    struct ProposalParameters {
        VotingMode votingMode;
        uint32 supportThreshold;
        uint64 startDate;
        uint64 endDate;
        uint64 snapshotBlock;
        uint256 minVotingPower;
    }

    /// @notice Emitted when votes are cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the vote.
    /// @param voteOptions The vote options casted by the voter.
    event VoteCast(uint256 indexed proposalId, address indexed voter, Tally voteOptions);

    /// @notice DEPRECATED: Emitted when a vote is cast by a voter.
    /// @dev Voters can now choose to split their votes across multiple options.
    event VoteCast(uint256 indexed, address indexed, VoteOption, uint256);

    /// @notice Returns the support threshold parameter stored in the voting settings.
    /// @return The support threshold parameter.
    function supportThreshold() external view returns (uint32);

    /// @notice Returns the minimum participation parameter stored in the voting settings.
    /// @return The minimum participation parameter.
    function minParticipation() external view returns (uint32);

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

    /// @notice Checks if an account can participate on a proposal vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the voter doesn't have voting powers.
    /// @param _proposalId The proposal Id.
    /// @param _account The account address to be checked.
    /// @param  _voteOptions Degree to which the voter abstains, supports or opposes the proposal.
    /// @return Returns true if the account is allowed to vote.
    /// @dev The function assumes the queried proposal exists.
    function canVote(
        uint256 _proposalId,
        address _account,
        Tally memory _voteOptions
    ) external view returns (bool);

    /// @notice overload of the above function that allows for a legacy vote option
    /// @param _voteOption The vote option to be checked.
    function canVote(
        uint256 _proposalId,
        address _account,
        VoteOption _voteOption
    ) external view returns (bool);

    /// @notice Checks if a proposal can be executed.
    /// @param _proposalId The ID of the proposal to be checked.
    /// @return True if the proposal can be executed, false otherwise.
    function canExecute(uint256 _proposalId) external view returns (bool);

    // BELOW INTERFACE DEFINITIONS ARE CAUSING SELECTOR CLASHES
    // THIS IS SOLIDITY BEING ANNOYING AND NEEDS A PROPER FIX
    // FOR NOW COMMENTING TO IGNORE THE ERROR

    /// @notice Votes for a set of vote options and, optionally, executes the proposal.
    /// @param _proposalId The ID of the proposal.
    /// @param _voteOptions The chosen vote options.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    /// The call does not revert if early execution is not possible.
    // function vote(uint256 _proposalId, Tally memory _voteOptions, bool _tryEarlyExecution) public;

    /// @notice Supports voting for a single vote options with full voting power using legacy voting
    // function vote(uint256 _proposalId, VoteOption _voteOption, bool _tryEarlyExecution) public;

    /// @notice Executes a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    function execute(uint256 _proposalId) external;

    /// @notice Returns the latest votes of the account for the proposal.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The account address to be checked.
    /// @return The vote options cast by a voter for the proposal.
    function getVoteOptions(
        uint256 _proposalId,
        address _account
    ) external view returns (Tally memory);

    /// @notice DEPRECATED: PLEASE USE `getVoteOptions` INSTEAD.
    /// @dev supports legacy queries for backwards compatibility and historical state.
    function getVoteOption(uint256, address) external view returns (VoteOption);
}

/// @dev we can't delete this just yet due to unresolved
/// bug with the interface not allowing overloads
interface IMajorityVotingV2 is IMajorityVoting {
    function vote(
        uint256 proposalId,
        IVoteContainer.Tally memory votes,
        bool tryEarlyExecution
    ) external;

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
}
