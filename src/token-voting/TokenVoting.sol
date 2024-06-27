// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IMembership} from "@aragon/osx/core/plugin/membership/IMembership.sol";
import {IProtocolVersion} from "@aragon/osx/utils/protocol/IProtocolVersion.sol";

import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {_applyRatioCeiled, RatioOutOfBounds, RATIO_BASE} from "@aragon/osx/plugins/utils/Ratio.sol";

import {ITokenVoting} from "./ITokenVoting.sol";
import {TallyMath} from "./libs/TallyMath.sol";
import {ProposalIdCodec} from "./libs/ProposalIdCodec.sol";

/// @title TokenVoting
/// @author Aragon X - 2021-2024
/// @notice The majority voting implementation using an
/// [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
/// compatible governance token.
/// @dev v2.0 (Release 2, Build 0)
/// @custom:security-contact sirt@aragon.org
contract TokenVoting is
    IMembership,
    ITokenVoting,
    Initializable,
    ERC165Upgradeable,
    PluginUUPSUpgradeable,
    ProposalUpgradeable
{
    using SafeCastUpgradeable for uint256;
    using SafeMathUpgradeable for uint256;
    using TallyMath for Tally;
    using ProposalIdCodec for uint256;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ---------- STATE ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant TOKEN_VOTING_INTERFACE_ID =
        this.initialize.selector ^
            this.getVotingToken.selector ^
            this.minDuration.selector ^
            this.minProposerVotingPower.selector ^
            this.votingMode.selector ^
            this.totalVotingPower.selector ^
            this.getProposal.selector ^
            this.updateVotingSettings.selector ^
            this.createProposal.selector;

    /// @notice The ID of the permission required to call the `updateVotingSettings` function.
    bytes32 public constant UPDATE_VOTING_SETTINGS_PERMISSION_ID =
        keccak256("UPDATE_VOTING_SETTINGS_PERMISSION");

    /// @notice A mapping between proposal IDs and proposal information.
    // solhint-disable-next-line named-parameters-mapping
    mapping(uint256 => Proposal) internal proposals;

    /// @dev TODO: added during offsite to allow aragonette to fetch via incrementing proposal IDs
    uint256[] public proposalIdsByCount;

    /// @notice The struct storing the voting settings.
    VotingSettings private votingSettings;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
    /// compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken;

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- ERRORS ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Thrown if a date is out of bounds.
    /// @param limit The limit value.
    /// @param actual The actual value.
    error DateOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown if the minimal duration value is out of bounds (less than one hour or greater than 1 year).
    /// @param limit The limit value.
    /// @param actual The actual value.
    error MinDurationOutOfBounds(uint64 limit, uint64 actual);

    /// @notice Thrown when a sender is not allowed to create a proposal.
    /// @param sender The sender address.
    error ProposalCreationForbidden(address sender);

    /// @notice Thrown if an account is not allowed to cast a vote. This can be because the vote
    /// - has not started,
    /// - has ended,
    /// - was executed, or
    /// - the account doesn't have sufficient voting power.
    /// @param proposalId The ID of the proposal.
    /// @param account The address of the _account.
    /// @param votes The chosen vote allocation.
    error VoteCastForbidden(uint256 proposalId, address account, Tally votes);

    /// @notice Thrown if the proposal execution is forbidden.
    /// @param proposalId The ID of the proposal.
    error ProposalExecutionForbidden(uint256 proposalId);

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- EVENTS ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Emitted when the voting settings are updated.
    /// @param votingMode A parameter to select the vote mode.
    /// @param supportThreshold The support threshold value.
    /// @param minParticipation The minimum participation value.
    /// @param minDuration The minimum duration of the proposal vote in seconds.
    /// @param minProposerVotingPower The minimum voting power required to create a proposal.
    event VotingSettingsUpdated(
        VotingMode votingMode,
        uint32 supportThreshold,
        uint32 minParticipation,
        uint64 minDuration,
        uint256 minProposerVotingPower
    );

    /// @notice Emitted when a vote is cast by a voter.
    /// @param proposalId The ID of the proposal.
    /// @param voter The voter casting the vote.
    /// @param votes The casted votes.
    /// @param votingPower The voting power behind this vote.
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        Tally votes,
        uint256 votingPower
    );

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ------- INITIALIZER -------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Initializes the component.
    /// @dev This method is required to support [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822).
    /// @param _dao The IDAO interface of the associated DAO.
    /// @param _votingSettings The voting settings.
    /// @param _token The [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token used for voting.
    function initialize(
        IDAO _dao,
        VotingSettings calldata _votingSettings,
        IVotesUpgradeable _token
    ) external initializer {
        __PluginUUPSUpgradeable_init(_dao);
        _updateVotingSettings(_votingSettings);

        votingToken = _token;

        emit MembershipContractAnnounced({definingContract: address(_token)});
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// ------ INTROSPECTION ------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        virtual
        override(ERC165Upgradeable, PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return
            _interfaceId == TOKEN_VOTING_INTERFACE_ID ||
            _interfaceId == type(IMembership).interfaceId ||
            _interfaceId == type(ITokenVoting).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- SETTINGS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @inheritdoc ITokenVoting
    function updateVotingSettings(
        VotingSettings calldata _votingSettings
    ) external virtual auth(UPDATE_VOTING_SETTINGS_PERMISSION_ID) {
        _updateVotingSettings(_votingSettings);
    }

    /// @notice Internal function to update the plugin-wide proposal vote settings.
    /// @param _votingSettings The voting settings to be validated and updated.
    function _updateVotingSettings(VotingSettings calldata _votingSettings) internal virtual {
        // Require the support threshold value to be in the interval [0, 10^6-1],
        // because `>` comparision is used in the support criterion and >100% could never be reached.
        if (_votingSettings.supportThreshold > RATIO_BASE - 1) {
            revert RatioOutOfBounds({
                limit: RATIO_BASE - 1,
                actual: _votingSettings.supportThreshold
            });
        }

        // Require the minimum participation value to be in the interval [0, 10^6],
        // because `>=` comparision is used in the participation criterion.
        if (_votingSettings.minParticipation > RATIO_BASE) {
            revert RatioOutOfBounds({limit: RATIO_BASE, actual: _votingSettings.minParticipation});
        }

        if (_votingSettings.minDuration < 60 minutes) {
            revert MinDurationOutOfBounds({limit: 60 minutes, actual: _votingSettings.minDuration});
        }

        if (_votingSettings.minDuration > 365 days) {
            revert MinDurationOutOfBounds({limit: 365 days, actual: _votingSettings.minDuration});
        }

        votingSettings = _votingSettings;

        emit VotingSettingsUpdated({
            votingMode: _votingSettings.votingMode,
            supportThreshold: _votingSettings.supportThreshold,
            minParticipation: _votingSettings.minParticipation,
            minDuration: _votingSettings.minDuration,
            minProposerVotingPower: _votingSettings.minProposerVotingPower
        });
    }

    /// @inheritdoc ITokenVoting
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @inheritdoc ITokenVoting
    function totalVotingPower(uint256 _blockNumber) public view returns (uint256) {
        return votingToken.getPastTotalSupply(_blockNumber);
    }

    /// @inheritdoc ITokenVoting
    function supportThreshold() public view virtual returns (uint32) {
        return votingSettings.supportThreshold;
    }

    /// @inheritdoc ITokenVoting
    function minParticipation() public view virtual returns (uint32) {
        return votingSettings.minParticipation;
    }

    /// @notice Returns the minimum duration parameter stored in the voting settings.
    /// @return The minimum duration parameter.
    function minDuration() public view virtual returns (uint64) {
        return votingSettings.minDuration;
    }

    /// @notice Returns the minimum voting power required to create a proposal stored in the voting settings.
    /// @return The minimum voting power required to create a proposal.
    function minProposerVotingPower() public view virtual returns (uint256) {
        return votingSettings.minProposerVotingPower;
    }

    /// @notice Returns the vote mode stored in the voting settings.
    /// @return The vote mode parameter.
    function votingMode() public view virtual returns (VotingMode) {
        return votingSettings.votingMode;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- PROPOSALS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @inheritdoc ITokenVoting
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        Tally memory _votes,
        bool _tryEarlyExecution
    ) external returns (uint256 proposalId) {
        // Check that either `_msgSender` owns enough tokens or has enough voting power from being a delegatee.
        {
            uint256 minProposerVotingPower_ = minProposerVotingPower();

            if (minProposerVotingPower_ != 0) {
                // Because of the checks in `TokenVotingSetup`, we can assume that `votingToken`
                // is an [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token.
                if (
                    votingToken.getVotes(_msgSender()) < minProposerVotingPower_ &&
                    IERC20Upgradeable(address(votingToken)).balanceOf(_msgSender()) <
                    minProposerVotingPower_
                ) {
                    revert ProposalCreationForbidden(_msgSender());
                }
            }
        }

        uint256 snapshotBlock;
        unchecked {
            // The snapshot block must be mined already to
            // protect the transaction against backrunning transactions causing census changes.
            snapshotBlock = block.number - 1;
        }

        uint256 totalVotingPower_ = totalVotingPower(snapshotBlock);

        if (totalVotingPower_ == 0) {
            revert NoVotingPower();
        }

        (_startDate, _endDate) = _validateProposalDates(_startDate, _endDate);

        proposalId = _createProposal({
            _creator: _msgSender(),
            _metadata: _metadata,
            _startDate: _startDate,
            _endDate: _endDate,
            _actions: _actions,
            _allowFailureMap: _allowFailureMap
        });

        // Store proposal related information
        Proposal storage proposal_ = proposals[proposalId];

        proposal_.parameters.startDate = _startDate;
        proposal_.parameters.endDate = _endDate;
        proposal_.parameters.snapshotBlock = snapshotBlock.toUint64();
        proposal_.parameters.votingMode = votingMode();
        proposal_.parameters.supportThreshold = supportThreshold();
        proposal_.parameters.minVotingPower = _applyRatioCeiled(
            totalVotingPower_,
            minParticipation()
        );

        // Reduce costs
        if (_allowFailureMap != 0) {
            proposal_.allowFailureMap = _allowFailureMap;
        }

        for (uint256 i; i < _actions.length; ) {
            proposal_.actions.push(_actions[i]);
            unchecked {
                ++i;
            }
        }

        if (!_votes.isZero()) {
            vote(proposalId, _votes, _tryEarlyExecution);
        }
    }

    /// @notice Internal function to create a proposal.
    /// @param _metadata The proposal metadata.
    /// @param _startDate The start date of the proposal in seconds.
    /// @param _endDate The end date of the proposal in seconds.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param _actions The actions that will be executed after the proposal passes.
    /// @return proposalId The ID of the proposal.
    function _createProposal(
        address _creator,
        bytes calldata _metadata,
        uint64 _startDate,
        uint64 _endDate,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap
    ) internal override returns (uint256 proposalId) {
        proposalId = _createProposalId({_startDate: _startDate, _endDate: _endDate});

        emit ProposalCreated({
            proposalId: proposalId,
            creator: _creator,
            metadata: _metadata,
            startDate: _startDate,
            endDate: _endDate,
            actions: _actions,
            allowFailureMap: _allowFailureMap
        });
    }

    /// @notice Creates a propsalId with timestamp and plugin data encoded. Also increases the proposal count.
    /// @dev This is a useful reference for timestamp based clocks on other chains.
    /// @param _startDate The start date of the proposal in seconds.
    /// @param _endDate The end date of the proposal in seconds.
    /// @return proposalId The ID of the proposal, encoded as plugin+timestamps.
    /// @dev The block timestamp is used rather than the block number as the block number is saved
    /// in the Propsal struct and only has meaning on this chain.
    function _createProposalId(
        uint64 _startDate,
        uint64 _endDate
    ) internal returns (uint256 proposalId) {
        _incrementProposalCount();

        proposalId = getProposalId({
            _startDate: _startDate,
            _endDate: _endDate,
            _snapshotBlockTimestamp: block.timestamp
        });

        // TODO: added to allow querying by count
        proposalIdsByCount.push(proposalId);

        return proposalId;
    }

    /// @notice Increases the total proposal count by one.
    /// @dev We cannot override `_createProposalId`, so this is a more idomatic way to increment the proposal count.
    function _incrementProposalCount() private {
        _createProposalId();
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- VOTING ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @inheritdoc ITokenVoting
    function vote(
        uint256 _proposalId,
        Tally memory _votes,
        bool _tryEarlyExecution
    ) public virtual {
        address account = _msgSender();

        if (!_canVote(_proposalId, account, _votes)) {
            revert VoteCastForbidden({proposalId: _proposalId, account: account, votes: _votes});
        }
        _vote(_proposalId, _votes, account, _tryEarlyExecution);
    }

    /// @notice Internal function to cast a vote. It assumes the queried vote exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _votes The chosen vote allocation to be casted on the proposal.
    /// @param _tryEarlyExecution If `true`,  early execution is tried after the vote cast.
    /// The call does not revert if early execution is not possible.
    function _vote(
        uint256 _proposalId,
        Tally memory _votes,
        address _voter,
        bool _tryEarlyExecution
    ) internal {
        Proposal storage proposal_ = proposals[_proposalId];
        Tally storage lastVotes = proposal_.voters[_voter];

        // Remove the previous vote of the voter if it exists
        if (!lastVotes.isZero()) proposal_.tally = proposal_.tally.sub(lastVotes);

        // Update the total votes of the proposal
        proposal_.tally = proposal_.tally.add(_votes);

        // write the updated/new vote for the voter.
        // done by field due to memory vs storage constraints
        lastVotes.yes = _votes.yes;
        lastVotes.no = _votes.no;
        lastVotes.abstain = _votes.abstain;

        emit VoteCast({
            proposalId: _proposalId,
            voter: _voter,
            votes: _votes,
            votingPower: _votes.sum()
        });

        if (_tryEarlyExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }

    /// @inheritdoc ITokenVoting
    function canVote(
        uint256 _proposalId,
        address _voter,
        Tally memory _votes
    ) public view virtual returns (bool) {
        return _canVote(_proposalId, _voter, _votes);
    }

    /// @notice Internal function to check if a voter can vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @param _account The address of the voter to check.
    /// @param  _votes To what degree the voter abstains, supports or opposes the proposal.
    /// @return Returns `true` if the given voter can vote on a certain proposal and `false` otherwise.
    function _canVote(
        uint256 _proposalId,
        address _account,
        Tally memory _votes
    ) internal view returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // The voter votes with zero votes which is not allowed.
        if (_votes.isZero()) {
            return false;
        }

        // The voter has insufficient voting power.
        if (votingToken.getPastVotes(_account, proposal_.parameters.snapshotBlock) < _votes.sum()) {
            return false;
        }

        // The voter has already voted but vote replacment is not allowed.
        if (
            !proposal_.voters[_account].isZero() &&
            proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return false;
        }

        return true;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- EXECUTION --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @inheritdoc ITokenVoting
    function execute(uint256 _proposalId) public virtual {
        if (!_canExecute(_proposalId)) {
            revert ProposalExecutionForbidden(_proposalId);
        }
        _execute(_proposalId);
    }

    /// @notice Internal function to execute a vote. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    function _execute(uint256 _proposalId) internal virtual {
        proposals[_proposalId].executed = true;

        _executeProposal(
            dao(),
            _proposalId,
            proposals[_proposalId].actions,
            proposals[_proposalId].allowFailureMap
        );
    }

    /// @inheritdoc ITokenVoting
    function canExecute(uint256 _proposalId) public view virtual returns (bool) {
        return _canExecute(_proposalId);
    }

    /// @notice Internal function to check if a proposal can be executed. It assumes the queried proposal exists.
    /// @param _proposalId The ID of the proposal.
    /// @return True if the proposal can be executed, false otherwise.
    /// @dev Threshold and minimal values are compared with `>` and `>=` comparators, respectively.
    function _canExecute(uint256 _proposalId) internal view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // Verify that the vote has not been executed already.
        if (proposal_.executed) {
            return false;
        }

        if (_isProposalOpen(proposal_)) {
            // Early execution
            if (proposal_.parameters.votingMode != VotingMode.EarlyExecution) {
                return false;
            }
            if (!isSupportThresholdReachedEarly(_proposalId)) {
                return false;
            }
        } else {
            // Normal execution
            if (!isSupportThresholdReached(_proposalId)) {
                return false;
            }
        }
        if (!isMinParticipationReached(_proposalId)) {
            return false;
        }

        return true;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- GETTERS ---------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must own at least one token or have at least one token delegated to her/him.
        return
            votingToken.getVotes(_account) > 0 ||
            IERC20Upgradeable(address(votingToken)).balanceOf(_account) > 0;
    }

    /// @inheritdoc ITokenVoting
    function getVotes(
        uint256 _proposalId,
        address _voter
    ) public view virtual returns (Tally memory) {
        return proposals[_proposalId].voters[_voter];
    }

    /// @inheritdoc ITokenVoting
    function getProposal(
        uint256 _proposalId
    )
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            Tally memory tally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        )
    {
        Proposal storage proposal_ = proposals[_proposalId];

        open = _isProposalOpen(proposal_);
        executed = proposal_.executed;
        parameters = proposal_.parameters;
        tally = proposal_.tally;
        actions = proposal_.actions;
        allowFailureMap = proposal_.allowFailureMap;
    }

    /// @dev TODO Added to keep API same when querying by autoincrementing counter
    function getProposalByIndex(
        uint _idx
    )
        public
        view
        virtual
        returns (
            bool open,
            bool executed,
            ProposalParameters memory parameters,
            Tally memory tally,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        )
    {
        uint proposalId = proposalIdsByCount[_idx];
        return getProposal(proposalId);
    }

    /// @inheritdoc ITokenVoting
    function isSupportThresholdReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * proposal_.tally.no;
    }

    /// @inheritdoc ITokenVoting
    function isSupportThresholdReachedEarly(
        uint256 _proposalId
    ) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        uint256 noVotesWorstCase = totalVotingPower(proposal_.parameters.snapshotBlock) -
            proposal_.tally.yes -
            proposal_.tally.abstain;

        // The code below implements the formula of the
        // early execution support criterion explained in the top of this file.
        // `(1 - supportThreshold) * N_yes > supportThreshold *  N_no,worst-case`
        return
            (RATIO_BASE - proposal_.parameters.supportThreshold) * proposal_.tally.yes >
            proposal_.parameters.supportThreshold * noVotesWorstCase;
    }

    /// @inheritdoc ITokenVoting
    function isMinParticipationReached(uint256 _proposalId) public view virtual returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        // The code below implements the formula of the
        // participation criterion explained in the top of this file.
        // `N_yes + N_no + N_abstain >= minVotingPower = minParticipation * N_total`
        return
            proposal_.tally.yes + proposal_.tally.no + proposal_.tally.abstain >=
            proposal_.parameters.minVotingPower;
    }

    /// @notice Internal function to check if a proposal vote is still open.
    /// @param proposal_ The proposal struct.
    /// @return True if the proposal vote is open, false otherwise.
    function _isProposalOpen(Proposal storage proposal_) internal view virtual returns (bool) {
        uint64 currentTime = block.timestamp.toUint64();

        return
            proposal_.parameters.startDate <= currentTime &&
            currentTime < proposal_.parameters.endDate &&
            !proposal_.executed;
    }

    /// @notice Validates and returns the proposal vote dates.
    /// @param _start The start date of the proposal vote.
    /// If 0, the current timestamp is used and the vote starts immediately.
    /// @param _end The end date of the proposal vote. If 0, `_start + minDuration` is used.
    /// @return startDate The validated start date of the proposal vote.
    /// @return endDate The validated end date of the proposal vote.
    function _validateProposalDates(
        uint64 _start,
        uint64 _end
    ) internal view virtual returns (uint64 startDate, uint64 endDate) {
        uint64 currentTimestamp = block.timestamp.toUint64();

        if (_start == 0) {
            startDate = currentTimestamp;
        } else {
            startDate = _start;

            if (startDate < currentTimestamp) {
                revert DateOutOfBounds({limit: currentTimestamp, actual: startDate});
            }
        }
        // Since `minDuration` is limited to 1 year,
        // `startDate + minDuration` can only overflow if the `startDate` is after `type(uint64).max - minDuration`.
        // In this case, the proposal creation will revert and another date can be picked.
        uint64 earliestEndDate = startDate + votingSettings.minDuration;

        if (_end == 0) {
            endDate = earliestEndDate;
        } else {
            endDate = _end;

            if (endDate < earliestEndDate) {
                revert DateOutOfBounds({limit: earliestEndDate, actual: endDate});
            }
        }
    }

    /// @inheritdoc ITokenVoting
    function getProposalId(
        uint256 _startDate,
        uint256 _endDate,
        uint256 _snapshotBlockTimestamp
    ) public view returns (uint256 proposalId) {
        return
            ProposalIdCodec.encode({
                _plugin: address(this),
                _proposalStartTimestamp: uint(_startDate).toUint32(),
                _proposalEndTimestamp: uint(_endDate).toUint32(),
                _proposalBlockSnapshotTimestamp: uint(_snapshotBlockTimestamp).toUint32()
            });
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[46] private __gap;
}
