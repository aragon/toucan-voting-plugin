// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";
import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanRelayMessage} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder, ProposalReference} from "@libs/ProposalRefEncoder.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver, MockToucanReceiverCanReceivePass} from "@mocks/MockToucanReceiver.sol";

import "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

contract TestToucanReceiverLzReceive is ToucanReceiverBaseTest, IToucanRelayMessage {
    using ProposalRefEncoder for uint256;
    using ProposalRefEncoder for ProposalReference;
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
        uint _proposalRef,
        bytes memory _reason,
        Tally memory _votes
    ) public {
        vm.assume(!_votes.isZero());

        // assume we have a valid ref
        (bool ok, ) = address(receiver).call(abi.encodeWithSignature("setRefValid(bool)", true));
        assertTrue(ok, "setRefValid failed");

        uint256 proposalId = _proposalRef.getProposalId();

        // submit votes reverts
        // This only works on calls not called as part of function execution
        // OR (in our case) when we use this.method() instead of method()
        vm.mockCallRevert({
            callee: address(receiver),
            data: abi.encodeCall(receiver.submitVotes, (proposalId)),
            revertData: _reason
        });

        ToucanVoteMessage memory message = ToucanVoteMessage({
            votingChainId: _votingChainId,
            proposalRef: _proposalRef,
            votes: _votes
        });

        // call the function
        vm.expectEmit(false, false, false, true);
        emit SubmitVoteFailed({
            proposalId: proposalId,
            votingChainId: _votingChainId,
            plugin: address(plugin),
            votes: _votes,
            revertData: _reason
        });

        Origin memory o;
        receiver._lzReceive(abi.encode(message), o, bytes(""));

        // check the votes are stored_proposaId
        Tally memory totalVotes = receiver.votes(proposalId);
        Tally memory chainVotes = receiver.votes(proposalId, _votingChainId);

        assertTrue(totalVotes.eq(_votes));
        assertTrue(chainVotes.eq(_votes));
    }

    function test_revertsIfInvalidRef(uint256 _proposalRef) public {
        bytes memory revertData = abi.encodeWithSelector(
            ToucanReceiver.InvalidProposalReference.selector,
            _proposalRef
        );

        bytes memory message = abi.encode(
            ToucanVoteMessage({votingChainId: 0, proposalRef: _proposalRef, votes: Tally(0, 0, 0)})
        );

        Origin memory o;

        vm.expectRevert(revertData);
        receiver._lzReceive(message, o, bytes(""));
    }

    function test_revertsIfCannotReceiveVotes() public {
        // use the real canreceive logic
        (bool ok, ) = address(receiver).call(
            abi.encodeWithSignature("setUseCanReceiveVotes(bool)", true)
        );
        assertTrue(ok, "setUseCanReceiveVotes failed");

        // assume valid ref
        (ok, ) = address(receiver).call(abi.encodeWithSignature("setRefValid(bool)", true));
        assertTrue(ok, "setRefValid failed");

        bytes memory revertData = abi.encodeWithSelector(
            ToucanReceiver.CannotReceiveVotes.selector,
            0,
            0,
            Tally(0, 0, 0),
            ToucanReceiver.ErrReason.ZeroVotes
        );

        bytes memory message = abi.encode(
            ToucanVoteMessage({votingChainId: 0, proposalRef: 0, votes: Tally(0, 0, 0)})
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
