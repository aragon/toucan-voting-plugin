// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {MajorityVotingBase, IMajorityVoting} from "src/voting/MajorityVotingBase.sol";
import {GovernanceERC20} from "src/token/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanRelayMessage} from "src/crosschain/toucanRelay/ToucanReceiver.sol";
import {ProposalIdCodec, ProposalId} from "@libs/ProposalIdCodec.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

import "forge-std/Test.sol";

contract MockToucanReceiverCanReceivePass is MockToucanReceiver {
    constructor(
        address _governanceToken,
        address _lzEndpoint,
        address _dao,
        address _votingPlugin
    ) MockToucanReceiver(_governanceToken, _lzEndpoint, _dao, _votingPlugin) {}

    function canReceiveVotes(
        uint256,
        Tally memory
    ) public pure override returns (bool, ToucanReceiver.ErrReason) {
        return (true, ErrReason.None);
    }
}

contract TestToucanReceiverLzReceive is ToucanReceiverBaseTest, IToucanRelayMessage {
    using ProposalIdCodec for uint256;
    using ProposalIdCodec for ProposalId;
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();
        receiver = new MockToucanReceiverCanReceivePass({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _votingPlugin: address(plugin)
        });
    }

    function _callLzReceive(bytes memory _message) internal {
        Origin memory o;
        receiver._lzReceive(_message, o, bytes(""));
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

        _callLzReceive(abi.encode(message));

        // check the votes are stored
        Tally memory totalVotes = receiver.votes(_proposalId);
        Tally memory chainVotes = receiver.getVotesByChain(_votingChainId, _proposalId);

        assertTrue(totalVotes.eq(_votes));
        assertTrue(chainVotes.eq(_votes));
    }
}
