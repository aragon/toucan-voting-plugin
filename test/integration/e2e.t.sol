// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

// aragon contracts
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {TokenVoting as ToucanVoting} from "@aragon/token-voting/TokenVoting.sol";
import {ITokenVoting, IVoteContainer} from "@aragon/token-voting/ITokenVoting.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";

// internal contracts
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

// internal test utils
import "utils/converters.sol";
import "forge-std/console2.sol";

import {MockDAOSimplePermission as MockDAO} from "test/mocks/MockDAO.sol";
import {AragonTest} from "test/base/AragonTest.sol";

uint256 constant _EVM_VOTING_CHAIN = 420;

/**
 * This contract tests the following E2E workflow
 * 1. Create a new gov token on the source chain
 * 2. Mint to 2 users, an execution voter and a voting voter
 * 3. The voting voter bridges the tokens to the destination chain
 * 4. The voting voter votes on a proposal, as does the execution voter
 * 5. We check the proposal status
 *
 * Note: we haven't (yet) setup the OSx infrastructure such as plugin setups and DAOs
 */
contract TestE2EToucan is TestHelper, AragonTest {
    using OptionsBuilder for bytes;
    using ProxyLib for address;
    using ProposalIdCodec for uint256;

    // execution chain
    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint256 constant EVM_EXECUTION_CHAIN = 137;

    address daoExecutionChain;
    GovernanceERC20 tokenExecutionChain;
    GovernanceOFTAdapter adapter;
    OFTTokenBridge bridge;
    ToucanReceiver receiver;
    address layerZeroEndpointExecutionChain;

    // voting chain
    uint32 constant EID_VOTING_CHAIN = 2;
    uint256 constant EVM_VOTING_CHAIN = _EVM_VOTING_CHAIN;

    address daoVotingChain;
    GovernanceERC20VotingChain tokenVotingChain;
    ToucanRelay relay;
    ToucanVoting plugin;
    address layerZeroEndpointVotingChain;

    // agents
    address executionVoter = address(0x69);
    address votingVoter = address(0x420);
    // cash they get in governance tokens
    uint constant INITIAL_MINT = 100 ether;

    // voting params
    uint32 constant SUPPORT_THRESHOLD = 1;
    uint32 constant MIN_PARTICIPATION = 1;
    uint64 constant MIN_DURATION = 3600;
    uint constant MIN_PROPOSER_VOTING_POWER = 1;
    ToucanVoting.VotingMode constant MODE = ITokenVoting.VotingMode.VoteReplacement;

    uint PROPOSAL_START_DATE = 10;

    function setUp() public override {
        // warp to genesis
        vm.warp(1);
        vm.roll(1);
        super.setUp();
        _initializeLzEndpoints();
        _deployExecutionChain();
        _deployVotingChain();
        _connectOApps();
        _addLabels();
        _grantLambos();
    }

    function test_itAllBaby() public {
        // the user needs to bridge first
        vm.startPrank(votingVoter);
        {
            _bridgeTokensToL2(50 ether, 250_000, votingVoter);
        }
        vm.stopPrank();

        // send it
        verifyBridge();
        assertEq(
            tokenVotingChain.balanceOf(votingVoter),
            50 ether,
            "voting voter should have 50 tokens on the voting chain"
        );
        assertEq(
            tokenExecutionChain.balanceOf(votingVoter),
            50 ether,
            "voting voter should haveg 50 tokens on the execution chain"
        );
        assertEq(
            tokenExecutionChain.balanceOf(executionVoter),
            100 ether,
            "execution voter should have 0 tokens on the execution chain"
        );

        // check the delegated balances
        assertEq(
            tokenExecutionChain.getVotes(votingVoter),
            50 ether,
            "voting voter should have 50 votes on execution chain"
        );
        assertEq(
            tokenExecutionChain.getVotes(executionVoter),
            100 ether,
            "execution voter should have 100 votes"
        );
        assertEq(
            tokenVotingChain.getVotes(votingVoter),
            50 ether,
            "voting voter should have 50 votes on voting chain"
        );
        assertEq(
            tokenExecutionChain.getVotes(address(receiver)),
            50 ether,
            "receiver should have 50 votes"
        );

        // start the next block
        vm.roll(2);

        // move to start date
        vm.warp(PROPOSAL_START_DATE);

        // now we make a proposal
        uint proposal;
        vm.startPrank(executionVoter);
        {
            proposal = createProposal(100 ether);
        }
        vm.stopPrank();

        assertEq(proposal.getPlugin(), address(plugin), "proposal should have the correct plugin");
        assertEq(
            proposal.getStartTimestamp(),
            PROPOSAL_START_DATE,
            "proposal should have the correct start timestamp"
        );
        assertEq(
            proposal.getEndTimestamp(),
            1680224400,
            "proposal should have the correct end timestamp"
        );

        // now we can try a vote on each chain
        vm.startPrank(executionVoter);
        {
            uint balance = tokenExecutionChain.balanceOf(executionVoter);
            plugin.vote(proposal, IVoteContainer.Tally({abstain: 0, yes: balance, no: 0}), false);
        }
        vm.stopPrank();

        // need to move the ts forward by one second to activate the vote
        vm.warp(block.timestamp + 1);

        vm.startPrank(votingVoter);
        {
            uint balance = tokenVotingChain.balanceOf(votingVoter);
            relay.vote(proposal, IVoteContainer.Tally({abstain: 0, yes: balance, no: 0}));
        }
        vm.stopPrank();

        // check the voting state
        // on the L1:
        {
            IVoteContainer.Tally memory p = getProposalTally(proposal);
            assertEq(p.yes, 100 ether, "proposal should have 100 votes");
            assertEq(p.no, 0, "proposal should have 0 no votes");
            assertEq(p.abstain, 0, "proposal should have 0 abstentions");
        }

        // on the L2 relayer
        {
            IVoteContainer.Tally memory p = relay.proposals(proposal);
            assertEq(p.yes, 50 ether, "proposal should have 50 votes");
            assertEq(p.no, 0, "proposal should have 0 no votes");
            assertEq(p.abstain, 0, "proposal should have 0 abstentions");
        }

        // send it cross chain
        {
            uint128 gasLimit = 200_000;
            ToucanRelay.LzSendParams memory params = relay.quote(
                proposal,
                EID_EXECUTION_CHAIN,
                gasLimit
            );
            relay.dispatchVotes{value: params.fee.nativeFee}(proposal, params);
        }

        // process it inside the recevier
        verifyReceiver();

        // check that the state in the receiver is updated correctly
        {
            IVoteContainer.Tally memory p = receiver.votes(proposal);
            assertEq(p.yes, 50 ether, "proposal should have 50 votes");
            assertEq(p.no, 0, "proposal should have 0 no votes");
            assertEq(p.abstain, 0, "proposal should have 0 abstentions");
        }

        // check the voting state is as expected
        {
            IVoteContainer.Tally memory p = getProposalTally(proposal);
            assertEq(p.yes, 150 ether, "proposal should have 100 votes");
            assertEq(p.no, 0, "proposal should have 0 no votes");
            assertEq(p.abstain, 0, "proposal should have 0 abstentions");
        }

        // send the tokens back to l1
        vm.startPrank(votingVoter);
        {
            _bridgeTokensToL1(50 ether, 250_000, votingVoter);
        }
        vm.stopPrank();

        verifyAdapter();

        {
            assertEq(
                tokenVotingChain.balanceOf(votingVoter),
                0,
                "voting voter should have 0 tokens on the voting chain"
            );
            assertEq(
                tokenExecutionChain.balanceOf(votingVoter),
                100 ether,
                "voting voter should have 100 tokens on the execution chain"
            );
        }

        // attempting to vote on the L1 will only increase the total by 50
        vm.startPrank(votingVoter);
        {
            plugin.vote(proposal, IVoteContainer.Tally({abstain: 0, yes: 50 ether, no: 0}), false);
        }
        vm.stopPrank();

        // voting state should be exactly 200
        {
            IVoteContainer.Tally memory p = getProposalTally(proposal);
            assertEq(p.yes, 200 ether, "proposal should have 200 votes");
            assertEq(p.no, 0, "proposal should have 0 no votes");
            assertEq(p.abstain, 0, "proposal should have 0 abstentions");
        }
    }

    function createProposal(uint _votesFor) public returns (uint256 proposalId) {
        IDAO.Action[] memory actions = new IDAO.Action[](1);
        actions[0] = IDAO.Action({
            to: address(this),
            value: 0,
            data: abi.encodeWithSignature("test_itWorks()")
        });
        ToucanVoting.Tally memory tally = IVoteContainer.Tally({abstain: 0, yes: _votesFor, no: 0});
        return
            plugin.createProposal({
                _metadata: bytes("0x"),
                _actions: actions,
                _allowFailureMap: 0,
                _startDate: 0, // start now
                _endDate: 1680224400,
                _tryEarlyExecution: false,
                _votes: tally
            });
    }

    function verifyBridge() public {
        verifyPackets(EID_VOTING_CHAIN, address(bridge));
    }

    function verifyRelay() public {
        verifyPackets(EID_VOTING_CHAIN, address(relay));
    }

    function verifyAdapter() public {
        verifyPackets(EID_EXECUTION_CHAIN, address(adapter));
    }

    function verifyReceiver() public {
        verifyPackets(EID_EXECUTION_CHAIN, address(receiver));
    }

    function _bridgeTokensToL1(uint _quantity, uint128 _gas, address _who) public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);
        SendParam memory sendParams = SendParam({
            dstEid: EID_EXECUTION_CHAIN,
            to: addressToBytes32(_who),
            amountLD: _quantity,
            minAmountLD: _quantity,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // fetch a quote
        MessagingFee memory msgFee = bridge.quoteSend(sendParams, false);

        // send the message
        tokenVotingChain.approve(address(bridge), _quantity);
        bridge.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
    }

    function _bridgeTokensToL2(uint _quantity, uint128 _gas, address _who) public {
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);
        SendParam memory sendParams = SendParam({
            dstEid: EID_VOTING_CHAIN,
            to: addressToBytes32(_who),
            amountLD: _quantity,
            minAmountLD: _quantity,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // fetch a quote
        MessagingFee memory msgFee = adapter.quoteSend(sendParams, false);

        // send the message
        tokenExecutionChain.approve(address(adapter), _quantity);
        adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
    }

    function _grantLambos() internal {
        vm.deal(votingVoter, 1000 ether);
        vm.deal(executionVoter, 1000 ether);
    }

    function _addLabels() internal {
        vm.label(executionVoter, "EXECUTION_VOTER");
        vm.label(votingVoter, "VOTING_VOTER");

        vm.label(daoExecutionChain, "DAO_EXECUTION_CHAIN");
        vm.label(daoVotingChain, "DAO_VOTING_CHAIN");

        vm.label(address(tokenVotingChain), "TOKEN_VOTING_CHAIN");
        vm.label(address(tokenExecutionChain), "TOKEN_EXECUTION_CHAIN");

        vm.label(layerZeroEndpointExecutionChain, "LZ_ENDPOINT_EXECUTION_CHAIN");
        vm.label(layerZeroEndpointVotingChain, "LZ_ENDPOINT_VOTING_CHAIN");
    }

    // call this first
    function _initializeLzEndpoints() internal {
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        layerZeroEndpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
        layerZeroEndpointVotingChain = endpoints[EID_VOTING_CHAIN];
    }

    function _deployPlugin(
        ToucanVoting.VotingSettings memory settings
    ) internal returns (ToucanVoting) {
        // deploy implementation
        address base = address(new ToucanVoting());
        // encode the initalizer
        bytes memory data = abi.encodeCall(
            ToucanVoting.initialize,
            (IDAO(daoExecutionChain), settings, IVotesUpgradeable(tokenExecutionChain))
        );
        // deploy and return the proxy
        address deployed = base.deployUUPSProxy(data);

        return ToucanVoting(deployed);
    }

    function _mintSettings(
        uint _qty
    ) internal view returns (GovernanceERC20.MintSettings memory settings) {
        address[] memory receivers = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        receivers[0] = executionVoter;
        amounts[0] = _qty;

        receivers[1] = votingVoter;
        amounts[1] = _qty;

        settings = GovernanceERC20.MintSettings(receivers, amounts);
        return settings;
    }

    function _deployExecutionChain() internal {
        // setup the dao
        daoExecutionChain = address(createMockDAO());

        // setup the token
        tokenExecutionChain = new GovernanceERC20(
            IDAO(daoExecutionChain),
            "Execution Token",
            "EXT",
            _mintSettings(INITIAL_MINT)
        );

        // initalize the adapter, receiver and plugin
        ToucanVoting.VotingSettings memory settings = ITokenVoting.VotingSettings({
            votingMode: MODE,
            supportThreshold: SUPPORT_THRESHOLD,
            minParticipation: MIN_PARTICIPATION,
            minDuration: MIN_DURATION,
            minProposerVotingPower: MIN_PROPOSER_VOTING_POWER
        });

        plugin = _deployPlugin(settings);

        receiver = new ToucanReceiver({
            _governanceToken: address(tokenExecutionChain),
            _lzEndpoint: layerZeroEndpointExecutionChain,
            _dao: daoExecutionChain,
            _votingPlugin: address(plugin)
        });

        adapter = new GovernanceOFTAdapter({
            _token: address(tokenExecutionChain),
            _voteProxy: address(receiver),
            _lzEndpoint: layerZeroEndpointExecutionChain,
            _dao: daoExecutionChain
        });

        // authorize the receiver to send to the plugin
        DAO(payable(daoExecutionChain)).grant({
            _where: address(receiver),
            _who: address(this),
            _permissionId: receiver.RECEIVER_ADMIN_ID()
        });
    }

    function _deployVotingChain() internal {
        daoVotingChain = address(createMockDAO());

        // setup the token
        tokenVotingChain = new GovernanceERC20VotingChain({
            _dao: IDAO(daoVotingChain),
            _name: "Voting Token",
            _symbol: "VOT"
        });

        // initalize the bridge and relay
        relay = new ToucanRelayVotingChain({
            _token: address(tokenVotingChain),
            _lzEndpoint: layerZeroEndpointVotingChain,
            _delegate: daoVotingChain
        });

        bridge = new OFTTokenBridge({
            _token: address(tokenVotingChain),
            _lzEndpoint: layerZeroEndpointVotingChain,
            _dao: daoVotingChain
        });

        // we need to allow the bridge to mint and burn tokens
        // todo - these should be done in the setup contracts.
        DAO(payable(daoVotingChain)).grant({
            _where: address(tokenVotingChain),
            _who: address(bridge),
            _permissionId: tokenVotingChain.MINT_PERMISSION_ID()
        });

        DAO(payable(daoVotingChain)).grant({
            _where: address(tokenVotingChain),
            _who: address(bridge),
            _permissionId: tokenVotingChain.BURN_PERMISSION_ID()
        });
    }

    function _connectOApps() internal {
        // the oftadapter and the bridge have a bidrectional relationship
        bridge.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(adapter)));
        adapter.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(bridge)));

        // the relayer can send to the receiver but not the other way around
        // regardless, they still need to be peers
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }

    function getProposalTally(
        uint256 _proposalId
    ) internal view returns (IVoteContainer.Tally memory tally) {
        (, , , tally, , ) = plugin.getProposal(_proposalId);
    }
}

/// override the chain id to be the voting chain
contract ToucanRelayVotingChain is ToucanRelay {
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) ToucanRelay(_token, _lzEndpoint, _delegate) {}

    function _chainId() internal pure override returns (uint) {
        return _EVM_VOTING_CHAIN;
    }
}

contract MyOFT is OFT {
    constructor(address _lzEndpoint, address _delegate) OFT("OFT", "OFT", _lzEndpoint, _delegate) {}
}
