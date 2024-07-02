// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Admin, AdminSetup} from "@aragon/admin/AdminSetup.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper as LzTestHelper} from "@lz-oapp-test/TestHelper.sol";

// own the libs
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {TallyMath} from "@libs/TallyMath.sol";

// internal contracts
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

/// execution chain
import {ToucanVoting, ToucanVotingSetup, IToucanVoting, GovernanceERC20, GovernanceWrappedERC20} from "@toucan-voting/ToucanVotingSetup.sol";
import {ToucanReceiver, ToucanReceiverSetup, GovernanceOFTAdapter} from "@execution-chain/setup/ToucanReceiverSetup.sol";

/// voting chain
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay, ToucanRelaySetup, OFTTokenBridge} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {AdminXChain, AdminXChainSetup} from "@voting-chain/setup/AdminXChainSetup.sol";

// utils
import "@utils/converters.sol";
import "@utils/deployers.sol";
import {SetupE2EBase, SetupExecutionChainE2E, SetupVotingChainE2E} from "src/e2e/E2ESetup.sol";

// test utils
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import "@helpers/OSxHelpers.sol";
import "forge-std/console2.sol";

/**
 * An E2E test of the entire Toucan voting system.
 * This covers the following:
 *
 * ✅ Deploying the contracts using plugin setups
 *  Bridging tokens
 *  ✅ forward
 *  - back
 *  ✅ Creating a proposal on the voting plugin
 *  ✅ Voting on the proposal,
 *   - remote x 2 chains
 *  - Simulating a brige delay
 *  - Sending an invalid proposal ref
 * - Changing to a new voting plugin, and ensuring votes are recorded accordingly
 * ✅ Voting on the proposal, locally
 * ✅ Executing the crosschain proposal to set a permission on the adminXchain
 *
 */
contract TestE2EFull is SetupExecutionChainE2E, SetupVotingChainE2E, LzTestHelper {
    using OptionsBuilder for bytes;

    address deployer = address(0x420);

    address eVoter = address(0x69);
    address vVoter0 = address(0x96);

    uint256 initialDeal = 1_000_000 ether;
    uint256 transferAmount = 100_000 ether;

    uint128 constant GAS_BRIDGE_TOKENS = 250_000;
    uint128 constant GAS_XCHAIN_PROPOSAL = 500_000;
    uint128 constant GAS_DISPATCH_VOTES = 500_000;

    uint proposalId;
    uint proposalRef;

    function testE2E() public {
        // reset clocks
        vm.warp(1);
        vm.roll(1);

        // initialize the chains
        ExecutionChain memory e = setupExecutionChain();
        VotingChain memory v = setupVotingChain();

        // deploy layerZero: this is cross chain
        _deployLayerZero(e.base, v.base);

        // setup the execution chain contracts
        _prepareSetupToucanVoting(e);
        _prepareSetupReceiver(e);
        _prepareUninstallAdmin(e.base);

        // setup the voting chain contracts
        _prepareSetupRelay(v);
        _prepareSetupAdminXChain(v);
        _prepareUninstallAdmin(v.base);

        // apply the installations and set the peers

        // exec chain
        _applyInstallationsSetPeersRevokeAdmin(e, v);

        // voting chain
        _applyInstallationsSetPeersRevokeAdmin(v, e);

        // give the agents cash money
        vm.deal(e.voter, initialDeal);
        vm.deal(v.voter, initialDeal);
        vm.deal(e.base.deployer, initialDeal);
        vm.deal(v.base.deployer, initialDeal);

        _addLabels(e, v);

        // first we want a user to bridge
        _bridgeTokens(e, v);
        // then we want to create a proposal
        _createProposal(e, v);
        // then do a vote
        // remote
        // bridge back
        _voteAndDispatch(e, v);

        // then execute the proposal, which will uninstall the xchain admin
        _executeBridgeProposal(e, v);

        // check the end state:
        // xchain admin should not have the permission
        assertFalse(
            v.base.dao.isGranted({
                _who: address(v.adminXChain),
                _where: address(v.base.dao),
                _permissionId: v.base.dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "xchainadmin should not have the permission"
        );
    }

    function setupExecutionChain() public returns (ExecutionChain memory e) {
        e.base.chainName = "Ethereum";
        e.base.chainid = 80085;
        e.base.deployer = deployer;
        e.voter = eVoter;

        _deployOSX(e.base);
        _deployDAOAndAdmin(e.base);
    }

    function setupVotingChain() public returns (VotingChain memory v) {
        v.base.chainName = "ZkSync";
        v.base.chainid = 1337;
        v.base.deployer = deployer;
        v.voter = vVoter0;

        _deployOSX(v.base);
        _deployDAOAndAdmin(v.base);
    }

    function _applyInstallationsSetPeersRevokeAdmin(
        ExecutionChain memory chain,
        VotingChain memory votingChain
    ) internal {
        IDAO.Action[] memory actions = _executionActions(chain, votingChain);

        // execute the actions
        vm.startPrank(chain.base.deployer);
        {
            chain.base.admin.executeProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0
            });
        }
        vm.stopPrank();
    }

    function _applyInstallationsSetPeersRevokeAdmin(
        VotingChain memory chain,
        ExecutionChain memory executionChain
    ) internal {
        IDAO.Action[] memory actions = _votingActions(chain, executionChain);

        // execute the actions
        vm.startPrank(chain.base.deployer);
        {
            chain.base.admin.executeProposal({
                _metadata: "",
                _actions: actions,
                _allowFailureMap: 0
            });
        }
        vm.stopPrank();
    }

    function _addLabels(ExecutionChain memory e, VotingChain memory v) internal {
        vm.label(e.voter, "execution-chain-voter");
        vm.label(v.voter, "voting-chain-voter");

        vm.label(e.base.deployer, "execution-chain-deployer");
        vm.label(v.base.deployer, "voting-chain-deployer");

        vm.label(address(e.token), "execution-chain-token");
        vm.label(address(v.token), "voting-chain-token");

        vm.label(address(e.adapter), "execution-chain-adapter");
        vm.label(address(v.bridge), "voting-chain-bridge");

        vm.label(address(e.receiver), "execution-chain-receiver");
        vm.label(address(v.relay), "voting-chain-relay");

        vm.label(address(e.voting), "execution-chain-voting");

        vm.label(address(v.adminXChain), "voting-chain-admin");
        vm.label(address(e.actionRelay), "execution-chain-action-relay");
    }

    function _deployLayerZero(
        ChainBase memory executionChain,
        ChainBase memory votingChain
    ) internal {
        setUpEndpoints(2, LibraryType.UltraLightNode);

        executionChain.eid = 1;
        executionChain.lzEndpoint = endpoints[executionChain.eid];
        assertNotEq(executionChain.lzEndpoint, address(0), "execution endpoint should not be 0");

        votingChain.eid = 2;
        votingChain.lzEndpoint = endpoints[votingChain.eid];
        assertNotEq(votingChain.lzEndpoint, address(0), "voting endpoint should not be 0");
    }

    // bridge tokens from the execution chain to the voting chain
    function _bridgeTokens(ExecutionChain memory e, VotingChain memory v) internal {
        // the execution chain voter should have 1_000_000 toekens
        assertEq(e.token.balanceOf(e.voter), initialDeal);

        // transfer to the voting chain voter
        vm.startPrank(e.voter);
        {
            e.token.transfer(v.voter, transferAmount);
            assertEq(e.token.balanceOf(v.voter), transferAmount);
        }
        vm.stopPrank();

        // send the tokens to the voting chain
        vm.startPrank(v.voter);
        {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
                GAS_BRIDGE_TOKENS,
                0
            );
            SendParam memory sendParams = SendParam({
                dstEid: v.base.eid,
                to: addressToBytes32(address(v.voter)),
                amountLD: transferAmount,
                minAmountLD: transferAmount,
                extraOptions: options,
                composeMsg: bytes(""),
                oftCmd: bytes("")
            });

            // fetch a quote
            MessagingFee memory msgFee = e.adapter.quoteSend(sendParams, false);
            assertEq(msgFee.lzTokenFee, 0, "lz fee should be 0");
            assertGt(msgFee.nativeFee, 0, "fee should be > 0");

            // send the message
            e.token.approve(address(e.adapter), transferAmount);
            e.adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
        }
        vm.stopPrank();

        // process the bridge transaction
        bridgeAdapterToOFTbridge(v);

        // check that the tokens were received
        assertEq(v.token.balanceOf(v.voter), transferAmount);
    }

    function _createProposal(ExecutionChain memory e, VotingChain memory v) internal {
        vm.roll(100);
        vm.warp(100);

        vm.startPrank(e.voter);
        {
            Tally memory votes = Tally(100_000, 200_000, 300_000);
            IDAO.Action[] memory actions = _createUninstallationProposal(e, v);

            proposalId = e.voting.createProposal({
                _metadata: "",
                _allowFailureMap: 0,
                _startDate: 0, // immediate
                _endDate: uint32(block.timestamp + 10 days),
                _tryEarlyExecution: false,
                _votes: votes,
                _actions: actions
            });
        }
        vm.stopPrank();

        // set the proposal ref
        proposalRef = e.receiver.getProposalRef(proposalId);
    }

    // note that the clocks are synced automatically
    function _voteAndDispatch(ExecutionChain memory e, VotingChain memory v) internal {
        // warp it forward 1 second to allow voting
        vm.warp(block.timestamp + 1);

        vm.startPrank(v.voter);
        {
            v.relay.vote(proposalRef, Tally(0, transferAmount, 0));

            // get a xchain quote
            ToucanRelay.LzSendParams memory quote = v.relay.quote(proposalRef, GAS_DISPATCH_VOTES);

            // dispatch it
            v.relay.dispatchVotes{value: quote.fee.nativeFee}(proposalRef, quote);
        }
        vm.stopPrank();

        // process the message
        bridgeRelayToReceiver(e);
    }

    function _executeBridgeProposal(ExecutionChain memory e, VotingChain memory v) internal {
        // ff to end of the proposal
        vm.warp(block.timestamp + 10 days);

        // execute the proposal
        vm.startPrank(e.voter);
        {
            // send the dao some cash to pay for the xchain fees
            (bool success, ) = address(payable(e.base.dao)).call{value: 10 ether}("");
            assertTrue(success, "should have sent the DAO some cash");

            e.voting.execute(proposalId);
        }
        vm.stopPrank();

        // process the message
        bridgeActionRelayToAdminXChain(v);
    }

    function bridgeAdapterToOFTbridge(VotingChain memory v) internal {
        verifyPackets(v.base.eid, address(v.bridge));
    }

    function bridgeOFTBridgeToAdapter(ExecutionChain memory e) internal {
        verifyPackets(e.base.eid, address(e.adapter));
    }

    function bridgeRelayToReceiver(ExecutionChain memory e) internal {
        verifyPackets(e.base.eid, address(e.receiver));
    }

    function bridgeActionRelayToAdminXChain(VotingChain memory v) internal {
        verifyPackets(v.base.eid, address(v.adminXChain));
    }

    function _createUninstallationProposal(
        ExecutionChain memory e,
        VotingChain memory v
    ) public view returns (IDAO.Action[] memory) {
        IDAO.Action[] memory innerActions = new IDAO.Action[](1);

        // these are executed on the voting chain
        innerActions[0] = IDAO.Action({
            to: address(v.base.dao),
            data: abi.encodeCall(
                v.base.dao.revoke,
                (
                    /* where */ address(v.base.dao),
                    /* who */ address(v.adminXChain),
                    /* permissionId */ v.base.dao.EXECUTE_PERMISSION_ID()
                )
            ),
            value: 0
        });

        // fetch a quote for all this
        ActionRelay.LzSendParams memory params = e.actionRelay.quote(
            e.voting.proposalCount(), // proposal id that will be created
            innerActions,
            0, // allowFailureMap
            v.base.eid,
            GAS_XCHAIN_PROPOSAL
        );

        // now we can create the execute action
        IDAO.Action[] memory actions = new IDAO.Action[](1);

        // the action on this chain will be to send to the action relay
        // the cross chain request
        actions[0] = IDAO.Action({
            to: address(e.actionRelay),
            data: abi.encodeCall(
                e.actionRelay.relayActions,
                (
                    e.voting.proposalCount(),
                    innerActions,
                    0, // allowFailureMap
                    params
                )
            ),
            // this is super important, it's not a zero value
            // transfer because the layer zero endpoint will
            // expect a fee from the DAO
            value: params.fee.nativeFee
        });

        return actions;
    }
}
