// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// external contracts
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

// aragon contracts
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";

// test utils
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";
import "@utils/deployers.sol";

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
    GovernanceERC20 token;

    MockToucanRelay relay;
    MockToucanReceiver receiver;
    MockToucanVoting plugin;

    function setUp() public override {
        super.setUp();
        vm.warp(0);
        vm.roll(0);
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            new address[](1),
            new uint256[](1)
        );
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 100 ether;
        token = new GovernanceERC20(IDAO(address(this)), "TestToken", "TT", mintSettings);

        plugin = deployMockToucanVoting();

        _initalizeOApps();

        relay.setChainId(EVM_VOTING_CHAIN);
    }

    function test_canSendAggregatedVotesAcrossTheNetwork() public {
        // initialize the vote we want to test
        uint abstentions = 10 ether;
        uint yesVotes = 20 ether;
        uint noVotes = 30 ether;
        // this fails with ~200k gas so it's not the cheapest
        uint128 gasLimit = 250_000;

        // send tokens to the receiver
        token.transfer(address(receiver), 100 ether);

        // encode a proposal id
        uint proposalId = ProposalIdCodec.encode(address(plugin), 0, 100, 1);

        plugin.setSnapshotBlock(proposalId, 1);

        // set the proposal vote
        relay.setProposalState(proposalId, Tally(abstentions, yesVotes, noVotes));

        // fetch a fee quote
        MockToucanRelay.LzSendParams memory params = relay.quote(
            proposalId,
            EID_EXECUTION_CHAIN,
            gasLimit
        );
        // move to ts 2
        vm.warp(2);
        vm.roll(2);

        // send the message
        relay.dispatchVotes{value: params.fee.nativeFee}(proposalId, params);

        // check the votes on the dst
        Tally memory aggregateVotes = receiver.votes(proposalId);

        assertEq(aggregateVotes.abstain, 0, "abstentions should be 0");
        assertEq(aggregateVotes.yes, 0, "yes votes should be 0");
        assertEq(aggregateVotes.no, 0, "no votes should be 0");

        // process the message
        verifyPackets(EID_EXECUTION_CHAIN, address(receiver));

        // check the votes on the dst
        aggregateVotes = receiver.votes(proposalId);

        assertEq(aggregateVotes.abstain, abstentions, "abstentions wrong");
        assertEq(aggregateVotes.yes, yesVotes, "yes votes wrong");
        assertEq(aggregateVotes.no, noVotes, "no votes wrong");

        // ensure we registered it against the right chain id
        Tally memory chainVotes = receiver.getVotesByChain({
            _proposalId: proposalId,
            _votingChainId: EVM_VOTING_CHAIN
        });

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

        relay = deployMockToucanRelay(address(1), endpointVotingChain, address(this));
        receiver = deployMockToucanReceiver(
            address(token),
            endpointExecutionChain,
            address(this),
            address(plugin)
        );

        // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }
}
