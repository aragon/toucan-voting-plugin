pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {ProposalIdCodec} from "./ProposalIdCodec.sol";

// todo replace this guy with standard iface
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {IMajorityVoting} from "src/v1/src/IMajorityVoting.sol";

interface IMajorityVotingV2 is IMajorityVoting {
    function vote(
        uint256 proposalId,
        ToucanReciever.Tally memory votes,
        bool tryEarlyExecution
    ) external;
}

contract ToucanReciever is OApp {
    address public governanceToken;

    /// this allows votes coming from a chain Id to be accepted after the end date
    /// intention is that there might be a delay in the receipt of the vote
    /// however we have to trust the source to enforce the end date
    mapping(uint256 votingChainId => bool allowed) public allowLateVotes;

    /// this will get replaced with OSx permissions
    modifier auth(bytes32) {
        _;
    }

    // this needs to be in an ITally interface as we use it everywhere
    // probably should rename it because anthony might kill himself
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }

    struct AggregateTally {
        mapping(uint256 chainId => Tally) votesByChain;
        Tally aggregateVotes;
    }

    mapping(uint256 proposalId => AggregateTally) votes;

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

    function adjustVote(uint _votingChainId, uint _proposalId, Tally memory _votes) public {
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

    // you realistically want anyone to be able to call this, in case
    function updateVote(uint _proposalId, bool _tryEarlyExecution) public {
        // get the current aggregate
        Tally memory aggregate = votes[_proposalId].aggregateVotes;

        (address plugin, , ) = ProposalIdCodec.decode(_proposalId);

        IMajorityVotingV2(plugin).vote(_proposalId, aggregate, _tryEarlyExecution);
    }

    /// @dev placeholder for the lzReceive function
    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal override {
        // deserialize inbound data
        // adjust vote
        // try/catch to send to proxy
    }
}
