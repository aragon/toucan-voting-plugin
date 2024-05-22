// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";
import {_applyRatioCeiled} from "@aragon/osx-commons-contracts/src/utils/math/Ratio.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {MajorityVotingBase} from "./MajorityVotingBase.sol";

import "forge-std/console2.sol";

/// @title TokenVoting
/// @author Aragon X - 2021-2023
/// @notice The majority voting implementation using an
/// [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
/// compatible governance token.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract TokenVoting is IMembership, MajorityVotingBase {
    using SafeCastUpgradeable for uint256;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    bytes4 internal constant TOKEN_VOTING_INTERFACE_ID =
        this.initialize.selector ^ this.getVotingToken.selector;

    /// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
    /// compatible contract referencing the token being used for voting.
    IVotesUpgradeable private votingToken;

    /// @notice Thrown if the voting power is zero
    error NoVotingPower();

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
        __MajorityVotingBase_init(_dao, _votingSettings);

        votingToken = _token;

        emit MembershipContractAnnounced({definingContract: address(_token)});
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == TOKEN_VOTING_INTERFACE_ID ||
            _interfaceId == type(IMembership).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice getter function for the voting token.
    /// @dev public function also useful for registering interfaceId
    /// and for distinguishing from majority voting interface.
    /// @return The token used for voting.
    function getVotingToken() public view returns (IVotesUpgradeable) {
        return votingToken;
    }

    /// @inheritdoc MajorityVotingBase
    function totalVotingPower(uint256 _blockNumber) public view override returns (uint256) {
        return votingToken.getPastTotalSupply(_blockNumber);
    }

    /// @inheritdoc MajorityVotingBase
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        VoteOption _voteOption,
        bool _tryEarlyExecution
    ) external override returns (uint256 proposalId) {
        proposalId = _createProposal(_metadata, _actions, _allowFailureMap, _startDate, _endDate);

        if (_voteOption != VoteOption.None) {
            vote(proposalId, _voteOption, _tryEarlyExecution);
        }

        return proposalId;
    }

    /// @inheritdoc MajorityVotingBase
    function createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate,
        Tally memory _voteOptions,
        bool _tryEarlyExecution
    ) external override returns (uint256 proposalId) {
        proposalId = _createProposal(_metadata, _actions, _allowFailureMap, _startDate, _endDate);

        if (_voteOptions.yes + _voteOptions.no + _voteOptions.abstain > 0) {
            vote(proposalId, _voteOptions, _tryEarlyExecution);
        }

        return proposalId;
    }

    /// @inheritdoc MajorityVotingBase
    function _createProposal(
        bytes calldata _metadata,
        IDAO.Action[] calldata _actions,
        uint256 _allowFailureMap,
        uint64 _startDate,
        uint64 _endDate
    ) internal override returns (uint256 proposalId) {
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

        return proposalId;
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        // A member must own at least one token or have at least one token delegated to her/him.
        return
            votingToken.getVotes(_account) > 0 ||
            IERC20Upgradeable(address(votingToken)).balanceOf(_account) > 0;
    }

    /// @inheritdoc MajorityVotingBase
    function _vote(
        uint256 _proposalId,
        Tally memory _voteOptions,
        address _voter,
        bool _tryEarlyExecution
    ) internal override {
        Proposal storage proposal_ = proposals[_proposalId];
        Tally memory state = proposal_.lastVotes[_voter];
        bool hasVoted = _totalVoteWeight(state) != 0;

        // If voter had previously voted, decrease count
        if (hasVoted) {
            proposal_.tally.abstain -= state.abstain;
            proposal_.tally.yes -= state.yes;
            proposal_.tally.no -= state.no;
        }

        // update the votes for the proposal
        proposal_.tally.abstain += _voteOptions.abstain;
        proposal_.tally.yes += _voteOptions.yes;
        proposal_.tally.no += _voteOptions.no;

        // write the updated/new vote for the voter.
        proposal_.lastVotes[_voter] = _voteOptions;

        // here we could emit the old event as well
        emit VoteCast({proposalId: _proposalId, voter: _voter, voteOptions: _voteOptions});

        if (_tryEarlyExecution && _canExecute(_proposalId)) {
            _execute(_proposalId);
        }
    }

    /// @inheritdoc MajorityVotingBase
    function _canVote(
        uint256 _proposalId,
        address _account,
        Tally memory _voteOptions
    ) internal view override returns (bool) {
        Proposal storage proposal_ = proposals[_proposalId];

        console2.log("cp1");
        // The proposal vote hasn't started or has already ended.
        if (!_isProposalOpen(proposal_)) {
            return false;
        }

        // this could re-enter with a malicious governance token
        uint votingPower = votingToken.getPastVotes(_account, proposal_.parameters.snapshotBlock);

        console2.log("cp2");
        // The voter has no voting power.
        if (votingPower == 0) {
            return false;
        }

        uint totalVoteWeight = _totalVoteWeight(_voteOptions);

        console2.log("cp3");
        console2.log("totalVoteWeight", totalVoteWeight);
        console2.log("votingPower", votingPower);
        // the user has insufficient voting power to vote
        if (totalVoteWeight > votingPower) {
            return false;
        }

        console2.log("cp4");
        // we reject zero votes
        if (totalVoteWeight == 0) {
            return false;
        }

        console2.log("cp5");
        // The voter has already voted but vote replacment is not allowed.
        if (
            _totalVoteWeight(proposal_.lastVotes[_account]) != 0 &&
            proposal_.parameters.votingMode != VotingMode.VoteReplacement
        ) {
            return false;
        }

        return true;
    }

    /// @inheritdoc MajorityVotingBase
    function _convertVoteOptionToTally(
        VoteOption _voteOption,
        uint256 _proposalId
    ) internal view override returns (Tally memory) {
        // this could re-enter with a malicious governance token
        Proposal storage proposal_ = proposals[_proposalId];
        uint votingPower = votingToken.getPastVotes(
            _msgSender(),
            proposal_.parameters.snapshotBlock
        );
        if (_voteOption == VoteOption.Abstain) {
            return Tally({abstain: votingPower, yes: 0, no: 0});
        } else if (_voteOption == VoteOption.Yes) {
            return Tally({abstain: 0, yes: votingPower, no: 0});
        } else if (_voteOption == VoteOption.No) {
            return Tally({abstain: 0, yes: 0, no: votingPower});
        } else {
            revert InvalidVoteOption(_voteOption);
        }
    }

    /// @dev This empty reserved space is put in place to allow future versions to add new
    /// variables without shifting down storage in the inheritance chain.
    /// https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
    uint256[49] private __gap;
}
