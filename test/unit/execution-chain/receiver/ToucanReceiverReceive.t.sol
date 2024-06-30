// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {ToucanVoting, IToucanVoting} from "@toucan-voting/ToucanVoting.sol";
import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder, ProposalReference} from "@libs/ProposalRefEncoder.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";
import "@utils/converters.sol";

import "forge-std/Test.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverReceive is ToucanReceiverBaseTest {
    using ProposalRefEncoder for uint256;
    using ProposalRefEncoder for ProposalReference;
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function setUp() public override {
        super.setUp();

        dao.grant({
            _who: address(this),
            _where: address(receiver),
            _permissionId: receiver.OAPP_ADMINISTRATOR_ID()
        });
    }

    function testFuzz_canReceiveRevertsOnZeroVotes(uint256 _proposalId) public view {
        Tally memory _votes = Tally(0, 0, 0);
        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.ZeroVotes);
    }

    function testFuzz_canReceiveRevertsOnInvalidProposalId(
        uint256 _proposalId,
        Tally memory _votes
    ) public {
        vm.assume(!_votes.isZero());
        plugin.setOpen(false);
        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.ProposalNotOpen);
    }

    function testFuzz_canReceiveRevertsOnInsufficientVotingPower(
        uint _proposalId,
        Tally memory _votes
    ) public {
        vm.assume(!_votes.isZero());
        vm.assume(!_votes.overflows());
        vm.assume(_votes.sum() > 0);

        plugin.setOpen(true);
        (bool success, ToucanReceiver.ErrReason reason) = receiver.canReceiveVotes(
            _proposalId,
            _votes
        );
        assertFalse(success);
        assertErrEq(reason, ToucanReceiver.ErrReason.InsufficientVotingPower);
    }

    // same as above but we need to ensure the voting power is sufficient
    function testFuzz_canReceiveVotesSuccess(uint _proposalId, Tally memory _votes) public {
        vm.assume(!_votes.isZero());
        vm.assume(!_votes.overflows());
        vm.assume(_votes.sum() > 0);
        vm.assume(_votes.sum() <= type(uint224).max); // erc20 votes are uint224

        // delegate some voting power to the receiver
        token.mint(address(receiver), _votes.sum());

        plugin.setOpen(true);

        // set the correct snapshot block on the proposal id to not be 0
        plugin.setSnapshotBlock(_proposalId, 1);

        // set to the right opening time
        vm.roll(2); // this allows for lookup @ time == 1

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
        emit VotesReceived(_proposalIds[0], _votingChainIds[0], address(plugin), v0);
        receiver.receiveVotes(_proposalIds[0], _votingChainIds[0], v0);

        // receive votes
        vm.expectEmit(false, false, false, true);
        emit VotesReceived(_proposalIds[1], _votingChainIds[1], address(plugin), v1);
        receiver.receiveVotes(_proposalIds[1], _votingChainIds[1], v1);

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

            assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[0]).eq(v0));
            assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[1]).eq(v1));

            // if the voting chains are equal then v{x} corresponds to proposalId
            if (votingChainsEqual) {
                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[1]).eq(v0));
                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[0]).eq(v1));
            }

            // else these should have no data
            if (!votingChainsEqual) {
                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[1]).isZero());
                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[0]).isZero());
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

                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[0]).eq(v0));
                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[1]).eq(v1));

                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[0]).eq(v0));
                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[1]).eq(v1));
            }

            if (votingChainsEqual) {
                assertTrue(aggregateVotesP0.eq(v1));

                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[0]).eq(v1));
                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[1]).eq(v1));

                assertTrue(receiver.votes(_proposalIds[0], _votingChainIds[1]).eq(v1));
                assertTrue(receiver.votes(_proposalIds[1], _votingChainIds[0]).eq(v1));
            }
        }
    }

    function testFuzz_receiveVotesAgainstAnotherPlugin(
        uint[2] memory _votingChainIds,
        uint[2] memory _proposalIds,
        Tally memory _votes,
        address _plugin,
        uint8 _divisor
    ) public {
        vm.assume(!_votes.overflows());
        vm.assume(_divisor != 0);
        vm.assume(_plugin != address(plugin));

        // divide votes into 2 parts
        Tally memory v0 = _votes.div(_divisor);
        Tally memory v1 = _votes.sub(v0);

        // receive votes
        vm.expectEmit(false, false, false, true);
        emit VotesReceived(_proposalIds[0], _votingChainIds[0], address(plugin), v0);
        receiver.receiveVotes(_proposalIds[0], _votingChainIds[0], v0);

        receiver.setVotingPlugin(_plugin);

        // receive votes
        vm.expectEmit(false, false, false, true);
        emit VotesReceived(_proposalIds[1], _votingChainIds[1], _plugin, v1);
        receiver.receiveVotes(_proposalIds[1], _votingChainIds[1], v1);

        // get the votes
        Tally memory votesP0 = receiver.votes(_proposalIds[0], _votingChainIds[0], address(plugin));
        Tally memory votesP1 = receiver.votes(_proposalIds[1], _votingChainIds[1], _plugin);

        // check they get stored correctly
        assertEq(votesP0.sum(), v0.sum());
        assertEq(votesP1.sum(), v1.sum());
    }
}
