// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import "@libs/TallyMath.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";

import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";

contract TestToucanRelayCanDispatch is ToucanRelayBaseTest {
    using TallyMath for Tally;
    using OverflowChecker for Tally;
    using ProposalRefEncoder for uint256;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_cannotDispatchBeforeStart(uint256 _proposalRef, uint32 _warpTo) public {
        // decode existing random proposal id
        uint32 _startTs = _proposalRef.getStartTimestamp();

        // assume that the startTs is greater than or equal the block ts we will move to
        vm.assume(_startTs >= _warpTo);

        // warp to the start
        vm.warp(_warpTo);

        (bool canDispatch, ToucanRelay.ErrReason reason) = relay.canDispatch({
            _proposalRef: _proposalRef
        });
        assertFalse(canDispatch);
        assertFalse(relay.isProposalOpen(_proposalRef));
        assertErrEq(reason, ToucanRelay.ErrReason.ProposalNotOpen);
    }

    function testFuzz_cannotDispatchAfterEnd(uint256 _proposalRef, uint32 _warpTo) public {
        // decode existing random proposal id
        uint32 _endTs = _proposalRef.getEndTimestamp();

        // assume that the endTs is less than or equal the block ts we will move to
        vm.assume(_endTs <= _warpTo);

        // warp to the end
        vm.warp(_warpTo);

        (bool canDispatch, ToucanRelay.ErrReason reason) = relay.canDispatch({
            _proposalRef: _proposalRef
        });
        assertFalse(canDispatch);
        assertErrEq(reason, ToucanRelay.ErrReason.ProposalNotOpen);
        assertFalse(relay.isProposalOpen(_proposalRef));
    }

    function testFuzz_cannotDispatchWithZeroWeight(uint256 _proposalSeed, uint32 _warpTo) public {
        uint _proposalRef = _makeValidProposalRefFromSeed(_proposalSeed);
        _warpToValidTs(_proposalRef, _warpTo);

        assertTrue(relay.isProposalOpen(_proposalRef), "Proposal should be open");

        (bool canDispatch, ToucanRelay.ErrReason reason) = relay.canDispatch({
            _proposalRef: _proposalRef
        });
        assertFalse(canDispatch);
        assertErrEq(reason, ToucanRelay.ErrReason.ZeroVotes);
    }

    function testFuzz_canDispatchIfData(
        uint256 _proposalSeed,
        uint32 _warpTo,
        Tally memory _tally
    ) public {
        uint _proposalRef = _makeValidProposalRefFromSeed(_proposalSeed);
        // check that 0 < sum(tally) < uint256 max
        vm.assume(!_tally.overflows());
        vm.assume(_tally.sum() > 0);

        // set the proposal state
        relay.setProposalState({_proposalRef: _proposalRef, _tally: _tally});

        // go to a valid time to dispatch
        _warpToValidTs(_proposalRef, _warpTo);
        assertTrue(relay.isProposalOpen(_proposalRef), "Proposal should be open");

        (bool canDispatch, ToucanRelay.ErrReason reason) = relay.canDispatch({
            _proposalRef: _proposalRef
        });

        assertTrue(canDispatch);
        assertErrEq(reason, ToucanRelay.ErrReason.None);
    }
}
