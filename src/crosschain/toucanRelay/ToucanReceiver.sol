pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {ProposalIdCodec} from "./ProposalIdCodec.sol";
import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

// todo replace this guy with standard iface
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMajorityVoting} from "src/voting/IMajorityVoting.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanRelayMessage} from "src/crosschain/toucanRelay/ToucanRelay.sol";

import "forge-std/console2.sol";

interface IMajorityVotingV2 is IMajorityVoting {
    function vote(
        uint256 proposalId,
        IVoteContainer.Tally memory votes,
        bool tryEarlyExecution
    ) external;
}

interface ILayerZeroEndpointV2Delegate {
    // mapping(address oapp => address delegate) public delegates;
    function delegates(address oapp) external view returns (address delegate);
}

/// TODO: what if toucan receiver gets manually delegated? Wonder if that will break things?
contract ToucanReceiver is OApp, IVoteContainer, DaoAuthorizable {
    struct AggregateTally {
        mapping(uint256 chainId => Tally) votesByChain;
        Tally aggregateVotes;
    }

    /// -------- EVENTS --------

    event VoteFailed(uint256 proposalId, bytes reason);

    /// -------- STATE --------

    /// @notice can set receiver admin and allow late votes
    bytes32 public constant RECEIVER_ADMIN_ID = keccak256("RECEIVER_ADMIN");

    /// @notice can collect refunds
    bytes32 public constant REFUND_COLLECTOR_ID = keccak256("REFUND_COLLECTOR");

    address public governanceToken;

    /// need to check this...
    mapping(address plugin => bool allowed) public authorizedPlugins;

    mapping(uint256 proposalId => AggregateTally) public votes;

    /// -------- CONSTRUCTOR & INITIALIZATION --------

    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) OApp(_lzEndpoint, _dao) DaoAuthorizable(IDAO(_dao)) {
        governanceToken = _governanceToken;
        authorizedPlugins[_votingPlugin] = true;
    }

    /// -------- ADMIN FUNCTIONS --------

    /// if this contract was set as the refund address, prevents locked funds
    /// funds are sent to the delegate
    /// we can just call the DAO
    function collectRefunds() external auth(REFUND_COLLECTOR_ID) {
        address dao = address(dao());
        (bool success, ) = payable(address(dao)).call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    /// @notice because the address is untrusted only the REFUND_COLLECTOR_ID can call this
    function collectRefunds(address _lzToken) external auth(REFUND_COLLECTOR_ID) {
        // transfer to DAO
        address dao = address(dao());
        IERC20(_lzToken).transfer(dao, IERC20(_lzToken).balanceOf(address(this)));
    }

    /// @notice updates the authorized plugin. We will call vote on this guy.
    function setAuthorizedPlugin(address _plugin, bool _authorized) public auth(RECEIVER_ADMIN_ID) {
        authorizedPlugins[_plugin] = _authorized;
    }

    /// --------- PUBLIC FUNCTIONS --------

    // you potentially want anyone to be able to call this to prevent a DoS
    function updateVote(uint _proposalId, bool _tryEarlyExecution) public {
        // get the current aggregate
        Tally memory aggregate = votes[_proposalId].aggregateVotes;

        uint total = aggregate.abstain + aggregate.yes + aggregate.no;

        require(total > 0, "no votes, check the proposal");

        (address plugin, , ) = ProposalIdCodec.decode(_proposalId);
        require(authorizedPlugins[plugin], "plugin not authorized");

        IMajorityVotingV2(plugin).vote(_proposalId, aggregate, _tryEarlyExecution);
    }

    /// ----------- LZ RECEIVE --------

    /// @dev placeholder for the lzReceive function
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {
        // deserialize inbound data
        IToucanRelayMessage.ToucanVoteMessage memory decoded = abi.decode(
            _message,
            (IToucanRelayMessage.ToucanVoteMessage)
        );

        uint srcChainId = decoded.srcChainId;
        uint proposalId = decoded.proposalId;
        Tally memory receivedVotes = decoded.votes;

        // adjust vote
        _adjustVote(srcChainId, proposalId, receivedVotes);

        // try/catch to send to proxy
        // TODO: do we want this
        try this.updateVote(proposalId, false) {} catch (bytes memory reason) {
            emit VoteFailed(proposalId, reason);
        }
    }

    function _adjustVote(uint _votingChainId, uint _proposalId, Tally memory _votes) internal {
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        require(startTimestamp <= block.timestamp, "u can't vote in the future");

        // there is an edge case where the vote may arrive after the endTimestamp
        // we need to explicitly cater for this
        require(endTimestamp >= block.timestamp, "u can't vote in the past");

        /// fetch the existing vote for the chain
        AggregateTally storage aggregateVotes = votes[_proposalId];
        Tally storage chainVotes = aggregateVotes.votesByChain[_votingChainId];

        /// remove the existing vote from the aggregate
        aggregateVotes.aggregateVotes.abstain -= chainVotes.abstain;
        aggregateVotes.aggregateVotes.yes -= chainVotes.yes;
        aggregateVotes.aggregateVotes.no -= chainVotes.no;

        /// add the new vote to the aggregate
        aggregateVotes.aggregateVotes.abstain += _votes.abstain;
        aggregateVotes.aggregateVotes.yes += _votes.yes;
        aggregateVotes.aggregateVotes.no += _votes.no;

        /// update the chain vote
        chainVotes.abstain = _votes.abstain;
        chainVotes.yes = _votes.yes;
        chainVotes.no = _votes.no;
    }

    /// ----------- VIEW FUNCTIONS --------

    function getVotesByChain(
        uint _proposalId,
        uint _votingChainId
    ) public view returns (Tally memory) {
        return votes[_proposalId].votesByChain[_votingChainId];
    }

    function getAggregateVotes(uint _proposalId) public view returns (Tally memory) {
        return votes[_proposalId].aggregateVotes;
    }

    // check that we've received delegation from the tokenBridge
    function isDelegate(address _tokenBridge) public view returns (bool) {
        return ERC20Votes(governanceToken).delegates(_tokenBridge) == address(this);
    }
}
