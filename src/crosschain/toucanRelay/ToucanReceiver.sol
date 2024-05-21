pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {ProposalIdCodec} from "./ProposalIdCodec.sol";

// todo replace this guy with standard iface
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
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

contract ToucanReceiver is OApp, IVoteContainer {
    address public governanceToken;

    /// this allows votes coming from a chain Id to be accepted after the end date
    /// intention is that there might be a delay in the receipt of the vote
    /// however we have to trust the source to enforce the end date
    mapping(uint256 votingChainId => bool allowed) public allowLateVotes;

    /// need to check this...
    mapping(address plugin => bool allowed) public authorizedPlugins;

    /// this will get replaced with OSx permissions
    modifier auth(bytes32) {
        _;
    }

    struct AggregateTally {
        mapping(uint256 chainId => Tally) votesByChain;
        Tally aggregateVotes;
    }

    mapping(uint256 proposalId => AggregateTally) public votes;

    function setLateVotes(
        bool _allowLateVotes,
        uint _votingChainId
    ) public auth(keccak256("RECEIVER_ADMIN_ROLE")) {
        allowLateVotes[_votingChainId] = _allowLateVotes;
    }

    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _delegate
    ) OApp(_lzEndpoint, _delegate) {
        governanceToken = _governanceToken;
    }

    function getVotesByChain(
        uint _proposalId,
        uint _votingChainId
    ) public view returns (Tally memory) {
        return votes[_proposalId].votesByChain[_votingChainId];
    }

    function getAggregateVotes(uint _proposalId) public view returns (Tally memory) {
        return votes[_proposalId].aggregateVotes;
    }

    function _adjustVote(uint _votingChainId, uint _proposalId, Tally memory _votes) internal {
        (, uint32 startTimestamp, uint32 endTimestamp) = ProposalIdCodec.decode(_proposalId);

        require(startTimestamp <= block.timestamp, "u can't vote in the future");
        // this is controversial: if we trust the source to enforce the end date, we don't need to check it
        // and it allows for post-hoc adjustments to the vote if there is a delay in receipt.
        // however it will also require adjustments in the tokenVoting contract
        if (!allowLateVotes[_votingChainId]) {
            require(endTimestamp >= block.timestamp, "u can't vote in the past");
        }

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

    // check that we've received delegation from the tokenBridge
    function isDelegate(address _tokenBridge) public view returns (bool) {
        return ERC20Votes(governanceToken).delegates(_tokenBridge) == address(this);
    }

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

    /// @dev placeholder for the lzReceive function
    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
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
    }

    /// if this contract was set as the refund address, prevents locked funds
    /// funds are sent to the delegate
    function collectRefunds() external auth(keccak256("REFUND_COLLECTOR_ID")) {
        address delegate = ILayerZeroEndpointV2Delegate(address(endpoint)).delegates(address(this));
        (bool success, ) = payable(delegate).call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    function collectRefunds(address _lzToken) external auth(keccak256("REFUND_COLLECTOR_ID")) {
        // transfer to DAO
    }
}
