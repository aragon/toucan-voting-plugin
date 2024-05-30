// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "src/token/governance/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import "@libs/TallyMath.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanRelay} from "@mocks/MockToucanRelay.sol";

import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";

contract TestToucanRelayCanDispatch is ToucanRelayBaseTest {
    using TallyMath for Tally;
    using OverflowChecker for Tally;
    using ProposalIdCodec for uint256;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_cannotDispatchBeforeStart(
        uint _executionChainId,
        uint256 _proposalId,
        uint32 _warpTo
    ) public {
        // decode existing random proposal id
        uint32 _startTs = _proposalId.getStartTimestamp();

        // assume that the startTs is greater than or equal the block ts we will move to
        vm.assume(_startTs >= _warpTo);

        // warp to the start
        vm.warp(_warpTo);

        bool canDispatch = relay.canDispatch({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId
        });
        assertFalse(canDispatch);
        assertFalse(relay.isProposalOpen(_proposalId));
    }

    function testFuzz_cannotDispatchAfterEnd(
        uint256 _executionChainId,
        uint256 _proposalId,
        uint32 _warpTo
    ) public {
        // decode existing random proposal id
        uint32 _endTs = _proposalId.getEndTimestamp();

        // assume that the endTs is less than or equal the block ts we will move to
        vm.assume(_endTs <= _warpTo);

        // warp to the end
        vm.warp(_warpTo);

        bool canDispatch = relay.canDispatch({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId
        });
        assertFalse(canDispatch);
        assertFalse(relay.isProposalOpen(_proposalId));
    }

    function testFuzz_cannotDispatchWithZeroWeight(
        uint256 _executionChainId,
        uint256 _proposalSeed,
        uint32 _warpTo
    ) public {
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);
        _warpToValidTs(_proposalId, _warpTo);

        assertTrue(relay.isProposalOpen(_proposalId), "Proposal should be open");

        bool canDispatch = relay.canDispatch({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId
        });
        assertFalse(canDispatch);
    }

    // check that we're checking the right chain against can dispatch
    function testFuzz_cannotDispatchIfZeroWeightFoundInIds(
        uint256 _executionChainId,
        uint256 _proposalSeed,
        uint32 _warpTo,
        Tally memory _tally
    ) public {
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);
        // check that 0 < sum(tally) < uint256 max
        vm.assume(!_tally.overflows());
        vm.assume(_tally.sum() > 0);

        // set the proposal state
        relay.setProposalState({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId,
            _tally: _tally
        });

        // go to a valid time to dispatch
        _warpToValidTs(_proposalId, _warpTo);
        assertTrue(relay.isProposalOpen(_proposalId), "Proposal should be open");

        // we do this to allow wrap around without overflow
        // we dont actually care about the value, just that it's not the same
        uint proposalIdPlusOne;
        uint executionIdPlusOne;
        unchecked {
            proposalIdPlusOne = _proposalId + 1;
            executionIdPlusOne = _executionChainId + 1;
        }

        bool canDispatch = relay.canDispatch({
            _proposalId: proposalIdPlusOne,
            _executionChainId: _executionChainId
        });

        assertFalse(canDispatch);

        canDispatch = relay.canDispatch({
            _proposalId: _proposalId,
            _executionChainId: executionIdPlusOne
        });

        assertFalse(canDispatch);

        canDispatch = relay.canDispatch({
            _proposalId: proposalIdPlusOne,
            _executionChainId: executionIdPlusOne
        });

        assertFalse(canDispatch);
    }

    function testFuzz_canDispatchIfData(
        uint256 _executionChainId,
        uint256 _proposalSeed,
        uint32 _warpTo,
        Tally memory _tally
    ) public {
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);
        // check that 0 < sum(tally) < uint256 max
        vm.assume(!_tally.overflows());
        vm.assume(_tally.sum() > 0);

        // set the proposal state
        relay.setProposalState({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId,
            _tally: _tally
        });

        // go to a valid time to dispatch
        _warpToValidTs(_proposalId, _warpTo);
        assertTrue(relay.isProposalOpen(_proposalId), "Proposal should be open");

        bool canDispatch = relay.canDispatch({
            _proposalId: _proposalId,
            _executionChainId: _executionChainId
        });

        assertTrue(canDispatch);
    }
}