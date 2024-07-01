// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

// external contracts
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

// aragon contracts
import {DAO} from "@aragon/osx/core/dao/DAO.sol";

import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IToucanVoting} from "@toucan-voting/IToucanVoting.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";

// test utils
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";
import {createTestDAO} from "@mocks/MockDAO.sol";
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
    using ProposalRefEncoder for uint256;

    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint256 constant EVM_EXECUTION_CHAIN = 137;
    uint256 constant EVM_VOTING_CHAIN = _EVM_VOTING_CHAIN;
    uint32 constant EID_VOTING_CHAIN = 2;
    GovernanceERC20 token;

    MockToucanRelay relay;
    MockToucanReceiver receiver;
    MockToucanProposal plugin;

    DAO dao;

    function setUp() public override {
        super.setUp();
        vm.warp(2);
        vm.roll(2);

        dao = createTestDAO(address(this));

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            new address[](1),
            new uint256[](1)
        );
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 100 ether;
        token = new GovernanceERC20(IDAO(address(dao)), "TestToken", "TT", mintSettings);

        plugin = deployMockToucanProposal();

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

        uint32 startDate = 1;
        uint32 endDate = 100;
        uint32 snapshotTs = 1;

        // send tokens to the receiver
        token.transfer(address(receiver), 100 ether);

        // encode a proposal reference
        uint proposalId = 100;
        uint proposalRef = ProposalRefEncoder.encode({
            _proposalId: uint32(proposalId),
            _plugin: address(plugin),
            _proposalStartTimestamp: startDate,
            _proposalEndTimestamp: endDate,
            _proposalBlockSnapshotTimestamp: snapshotTs
        });

        plugin.setParameters(
            proposalId,
            IToucanVoting.ProposalParameters({
                votingMode: IToucanVoting.VotingMode.VoteReplacement,
                supportThreshold: 50,
                startDate: startDate,
                endDate: endDate,
                snapshotBlock: 2,
                snapshotTimestamp: snapshotTs,
                minVotingPower: 100
            })
        );

        // set the proposal vote
        relay.setProposalState(proposalRef, Tally(abstentions, yesVotes, noVotes));

        // open the proposal, this is a mock
        plugin.setOpen(true);

        // fetch a fee quote
        MockToucanRelay.LzSendParams memory params = relay.quote(proposalRef, gasLimit);
        // move to ts 3
        vm.warp(3);
        vm.roll(3);

        // send the message
        relay.dispatchVotes{value: params.fee.nativeFee}(proposalRef, params);

        // check the votes on the dst
        Tally memory aggregateVotes = receiver.votes(proposalId);

        assertEq(aggregateVotes.abstain, 0, "abstentions should be 0");
        assertEq(aggregateVotes.yes, 0, "yes votes should be 0");
        assertEq(aggregateVotes.no, 0, "no votes should be 0");

        // process the message
        verifyPackets(EID_EXECUTION_CHAIN, address(receiver));

        // check the votes on the dst
        aggregateVotes = receiver.votes(proposalId);

        assertEq(aggregateVotes.abstain, abstentions, "abstentions wrong agg");
        assertEq(aggregateVotes.yes, yesVotes, "yes votes wrong agg");
        assertEq(aggregateVotes.no, noVotes, "no votes wrong agg");

        // ensure we registered it against the right chain id
        Tally memory chainVotes = receiver.votes({
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

        relay = deployMockToucanRelay(
            address(1),
            endpointVotingChain,
            address(dao),
            EID_EXECUTION_CHAIN,
            0
        );
        receiver = deployMockToucanReceiver(
            address(token),
            endpointExecutionChain,
            address(dao),
            address(plugin)
        );

        // grant permissions
        dao.grant({
            _who: address(this),
            _permissionId: relay.OAPP_ADMINISTRATOR_ID(),
            _where: address(relay)
        });

        dao.grant({
            _who: address(this),
            _permissionId: receiver.OAPP_ADMINISTRATOR_ID(),
            _where: address(receiver)
        });

        // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }
}
