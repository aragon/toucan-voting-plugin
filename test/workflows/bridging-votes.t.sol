// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// external contracts
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

// aragon contracts
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {ToucanReceiver} from "src/crosschain/toucanRelay/ToucanReceiver.sol";

// test utils
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";

// share with mock by making it a constant at global level
uint256 constant _EVM_VOTING_CHAIN = 420;

/**
 * This test verifies the aggregator on the voting chain can send votes to the execution chain via layer zero.
 * We want to be precise here, so we will mock the following:
 * 1. We create a mock that allows direct writes to the storage of the voting aggregator.
 * 2. We send across the bridge.
 * `3. We verify the state of votes in the aggregator
 *
 * We're not testing delegated balance, or the ability to vote on the execution chain.
 * We WILL test sending from 2 chains to the execution chain.
 */
contract TestBridgingVotesCrossChain is TestHelper, IVoteContainer {
    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint256 constant EVM_EXECUTION_CHAIN = 137;
    uint256 constant EVM_VOTING_CHAIN = _EVM_VOTING_CHAIN;
    uint32 constant EID_VOTING_CHAIN = 2;

    MockToucanRelay relay;
    MockToucanReceiver receiver;

    function setUp() public override {
        super.setUp();
        _initalizeOApps();
    }

    function test_canSendAggregatedVotesAcrossTheNetwork() public {
        // initialize the vote we want to test
        uint abstentions = 10 ether;
        uint yesVotes = 20 ether;
        uint noVotes = 30 ether;
        // this fails with ~150k gas so it's not the cheapest
        uint128 gasLimit = 200_000;

        // encode a proposal id
        uint proposalId = ProposalIdCodec.encode(address(1), 0, 100, 0);

        // set the proposal vote
        relay.setProposalVote(proposalId, Tally(abstentions, yesVotes, noVotes));

        // fetch a fee quote
        ToucanRelay.LzSendParams memory params = relay.quote(
            proposalId,
            EID_EXECUTION_CHAIN,
            gasLimit
        );
        // move to ts 1
        vm.warp(1);

        // send the message
        relay.dispatchVotes{value: params.fee.nativeFee}(proposalId, params);

        // check the votes on the dst
        Tally memory aggregateVotes = receiver.getAggregateVotes(proposalId);

        assertEq(aggregateVotes.abstain, 0, "abstentions should be 0");
        assertEq(aggregateVotes.yes, 0, "yes votes should be 0");
        assertEq(aggregateVotes.no, 0, "no votes should be 0");

        // process the message
        verifyPackets(EID_EXECUTION_CHAIN, address(receiver));

        // check the votes on the dst
        aggregateVotes = receiver.getAggregateVotes(proposalId);

        assertEq(aggregateVotes.abstain, abstentions, "abstentions wrong");
        assertEq(aggregateVotes.yes, yesVotes, "yes votes wrong");
        assertEq(aggregateVotes.no, noVotes, "no votes wrong");

        // ensure we registered it against the right chain id
        Tally memory chainVotes = receiver.getVotesByChain(proposalId, EVM_VOTING_CHAIN);

        assertEq(chainVotes.abstain, abstentions, "abstentions wrong");
        assertEq(chainVotes.yes, yesVotes, "yes votes wrong");
        assertEq(chainVotes.no, noVotes, "no votes wrong");
    }

    function _initalizeOApps() private {
        // 1. setup 2 endpoints
        // code for simple message lib is much simpler
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        address endpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
        address endpointVotingChain = endpoints[EID_VOTING_CHAIN];

        relay = new MockToucanRelay(address(0), endpointVotingChain, address(this));
        receiver = new MockToucanReceiver(
            address(0),
            endpointExecutionChain,
            address(this),
            address(0)
        );

        // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }
}

contract MockToucanRelay is ToucanRelay {
    constructor(
        address _token,
        address _lzEndpoint,
        address _dao
    ) ToucanRelay(_token, _lzEndpoint, _dao) {}

    /// update global state before sending
    function setProposalVote(uint256 _proposalId, Tally calldata _votes) external {
        proposals[_proposalId].tally.abstain = _votes.abstain;
        proposals[_proposalId].tally.yes = _votes.yes;
        proposals[_proposalId].tally.no = _votes.no;
    }

    function _chainId() internal pure override returns (uint256) {
        return _EVM_VOTING_CHAIN;
    }
}

contract MockToucanReceiver is ToucanReceiver {
    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) ToucanReceiver(_governanceToken, _lzEndpoint, _dao, _votingPlugin) {}
}
