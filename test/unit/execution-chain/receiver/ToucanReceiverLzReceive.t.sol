// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {TokenVoting, ITokenVoting} from "@aragon/token-voting/TokenVoting.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanRelayMessage} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalIdCodec, ProposalId} from "@libs/ProposalIdCodec.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver, MockToucanReceiverCanReceivePass} from "@mocks/MockToucanReceiver.sol";

import "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

import "forge-std/Test.sol";

contract TestToucanReceiverLzReceive is ToucanReceiverBaseTest, IToucanRelayMessage {
    using ProposalIdCodec for uint256;
    using ProposalIdCodec for ProposalId;
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();

        address base = address(new MockToucanReceiverCanReceivePass());
        bytes memory data = abi.encodeCall(
            ToucanReceiver.initialize,
            (address(token), address(lzEndpoint), address(dao), address(plugin))
        );
        address deployed = ProxyLib.deployUUPSProxy(base, data);

        receiver = MockToucanReceiverCanReceivePass(payable(deployed));
    }

    // stores the votes if submitVotes fails and emits the event
    function testFuzz_storesVotesIfSubmitFails(
        uint _votingChainId,
        uint _proposalId,
        bytes memory _reason,
        Tally memory _votes
    ) public {
        vm.assume(!_votes.isZero());

        // submit votes reverts
        // This only works on calls not called as part of function execution
        // OR (in our case) when we use this.method() instead of method()
        vm.mockCallRevert({
            callee: address(receiver),
            data: abi.encodeCall(receiver.submitVotes, (_proposalId)),
            revertData: _reason
        });

        ToucanVoteMessage memory message = ToucanVoteMessage({
            votingChainId: _votingChainId,
            proposalId: _proposalId,
            votes: _votes
        });

        // call the function
        vm.expectEmit(false, false, false, true);
        emit SubmitVoteFailed({
            votingChainId: _votingChainId,
            proposalId: _proposalId,
            votes: _votes,
            revertData: _reason
        });

        Origin memory o;
        receiver._lzReceive(abi.encode(message), o, bytes(""));

        // check the votes are stored
        Tally memory totalVotes = receiver.votes(_proposalId);
        Tally memory chainVotes = receiver.getVotesByChain(_votingChainId, _proposalId);

        assertTrue(totalVotes.eq(_votes));
        assertTrue(chainVotes.eq(_votes));
    }

    function test_revertsIfCannotReceiveVotes() public {
        // we need the real receiver in this case
        receiver = deployMockToucanReceiver({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _votingPlugin: address(plugin)
        });

        bytes memory revertData = abi.encodeWithSelector(
            ToucanReceiver.CannotReceiveVotes.selector,
            0,
            0,
            Tally(0, 0, 0),
            ToucanReceiver.ErrReason.ZeroVotes
        );

        bytes memory message = abi.encode(
            ToucanVoteMessage({votingChainId: 0, proposalId: 0, votes: Tally(0, 0, 0)})
        );

        Origin memory o;

        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            0,
            Tally(0, 0, 0)
        );

        assertFalse(success);
        assertEq(uint(reason), uint(ToucanReceiver.ErrReason.ZeroVotes));

        vm.expectRevert(revertData);
        receiver._lzReceive(message, o, bytes(""));
    }
}
