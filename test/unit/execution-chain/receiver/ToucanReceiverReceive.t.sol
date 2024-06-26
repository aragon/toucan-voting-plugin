// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {TokenVoting, ITokenVoting} from "@aragon/token-voting/TokenVoting.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalIdCodec, ProposalId} from "@libs/ProposalIdCodec.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

import "forge-std/Test.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverReceive is ToucanReceiverBaseTest {
    using ProposalIdCodec for uint256;
    using ProposalIdCodec for ProposalId;
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_canReceiveRevertsOnZeroVotes(uint _proposalSeed) public view {
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);
        Tally memory _votes = Tally(0, 0, 0);
        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.ZeroVotes);
    }

    function testFuzz_canReceiveRevertsOnInvalidProposalId(Tally memory _votes) public view {
        vm.assume(!_votes.isZero());
        uint _proposalId = ProposalIdCodec.encode(address(0), 1, 0, 0);
        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.InvalidProposalId);
    }

    function testFuzz_canReceiveRevertsOnInsufficientVotingPower(
        uint _proposalSeed,
        Tally memory _votes
    ) public {
        vm.assume(!_votes.isZero());
        vm.assume(!_votes.overflows());
        vm.assume(_votes.sum() > 0);
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);

        // write the voting plugin address to the proposal id
        ProposalId memory p = _proposalId.toStruct();
        p.plugin = address(plugin);
        _proposalId = p.fromStruct();

        // set to the right opening time
        uint32 openingTime = _proposalId.getStartTimestamp();
        vm.warp(openingTime + 1);

        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.InsufficientVotingPower);
    }

    // same as above but we need to ensure the voting power is sufficient
    function testFuzz_canReceiveVotesSuccess(uint _proposalSeed, Tally memory _votes) public {
        vm.assume(!_votes.isZero());
        vm.assume(!_votes.overflows());
        vm.assume(_votes.sum() > 0);
        vm.assume(_votes.sum() <= type(uint224).max); // erc20 votes are uint224

        // delegate some voting power to the receiver
        token.mint(address(receiver), _votes.sum());

        // create a valid proposal id
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);

        // write the voting plugin address to the proposal id
        ProposalId memory p = _proposalId.toStruct();
        p.plugin = address(plugin);
        _proposalId = p.fromStruct();

        // set the correct snapshot block on the proposal id to not be 0
        plugin.setSnapshotBlock(_proposalId, 1);

        // set to the right opening time
        uint32 openingTime = _proposalId.getStartTimestamp();
        vm.roll(2); // this allows for lookup @ time == 1
        vm.warp(openingTime + 1);

        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertTrue(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.None);
    }

    // this function uses a mock receiver to directly call the _receiveVotes function
    // so we don't need to setup a valid state and can just test the accounting
    function testFuzz_receiveVotes(
        uint[2] memory _votingChainIds,
        uint[2] memory _proposalIds,
        Tally memory _votes,
        uint8 _divisor
    ) public {
        vm.assume(!_votes.overflows());
        vm.assume(_divisor != 0);

        // divide votes into 2 parts
        Tally memory v0 = _votes.div(_divisor);
        Tally memory v1 = _votes.sub(v0);

        // receive votes
        vm.expectEmit(false, false, false, true);
        emit VotesReceived(_votingChainIds[0], _proposalIds[0], v0);
        receiver.receiveVotes(_votingChainIds[0], _proposalIds[0], v0);

        // receive votes
        vm.expectEmit(false, false, false, true);
        emit VotesReceived(_votingChainIds[1], _proposalIds[1], v1);
        receiver.receiveVotes(_votingChainIds[1], _proposalIds[1], v1);

        // get the votes
        Tally memory aggregateVotesP0 = receiver.votes(_proposalIds[0]);
        Tally memory aggregateVotesP1 = receiver.votes(_proposalIds[1]);

        // check they get stored correctly
        bool votingChainsEqual = _votingChainIds[0] == _votingChainIds[1];
        bool proposalIdsEqual = _proposalIds[0] == _proposalIds[1];

        // we first test the proposal ids as, if they are different
        // the voting chains should be irrelevant when it comes to aggregation
        if (!proposalIdsEqual) {
            assertTrue(aggregateVotesP0.eq(v0));
            assertTrue(aggregateVotesP1.eq(v1));

            // if the votes are the same, the aggregates should be the same
            // in all other cases, they should be different
            if (v1.eq(v0)) {
                assertTrue(aggregateVotesP0.eq(aggregateVotesP1));
            } else {
                assertFalse(aggregateVotesP0.eq(aggregateVotesP1));
            }

            assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[0]).eq(v0));
            assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[1]).eq(v1));

            // if the voting chains are equal then v{x} corresponds to proposalId
            if (votingChainsEqual) {
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[0]).eq(v0));
                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[1]).eq(v1));
            }

            // else these should have no data
            if (!votingChainsEqual) {
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[0]).isZero());
                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[1]).isZero());
            }
        }

        // if proposal ids are equal, then there are 2 cases:
        // 1. The voting chains are different, we should see a straight aggregate
        // But the votes by chain are different
        // 2. The voting chains are the same, we should see replacement
        // And the votes by chain will be the latest vote
        if (proposalIdsEqual) {
            assertTrue(aggregateVotesP1.eq(aggregateVotesP0));

            if (!votingChainsEqual) {
                assertTrue(aggregateVotesP0.eq(v0.add(v1)));

                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[0]).eq(v0));
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[1]).eq(v1));

                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[1]).eq(v0));
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[0]).eq(v1));
            }

            if (votingChainsEqual) {
                assertTrue(aggregateVotesP0.eq(v1));

                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[0]).eq(v1));
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[1]).eq(v1));

                assertTrue(receiver.getVotesByChain(_votingChainIds[0], _proposalIds[1]).eq(v1));
                assertTrue(receiver.getVotesByChain(_votingChainIds[1], _proposalIds[0]).eq(v1));
            }
        }
    }
}
