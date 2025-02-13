// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder, ProposalReference} from "@libs/ProposalRefEncoder.sol";

import "forge-std/Test.sol";
import "@utils/converters.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverSubmitVotes is ToucanReceiverBaseTest {
    using ProposalRefEncoder for uint256;
    using ProposalRefEncoder for ProposalReference;

    function setUp() public override {
        super.setUp();

        dao.grant({
            _who: address(this),
            _where: address(receiver),
            _permissionId: receiver.OAPP_ADMINISTRATOR_ID()
        });
    }

    // reverts if nothing to submit
    function testFuzz_revertsIfNothingToSubmit(uint _proposalSeed) public {
        uint _proposalId = _makeValidProposalRefFromSeed(_proposalSeed);

        // address vp = _proposalId.getPlugin();
        uint32 openingTime = _proposalId.getStartTimestamp();

        vm.warp(openingTime + 1);

        // receiver.setVotingPlugin(vp);

        // write the voting plugin address to the proposal id
        vm.expectRevert(
            abi.encodeWithSelector(ToucanReceiver.NoVotesToSubmit.selector, _proposalId)
        );
        receiver.submitVotes(_proposalId);
    }

    // calls the vote function with the expected values
    function testFuzz_callsVoteWithExpectedValues(uint _proposalSeed, Tally memory _votes) public {
        uint _proposalId = _makeValidProposalRefFromSeed(_proposalSeed);

        // write the voting plugin address to the proposal id
        ProposalReference memory p = _proposalId.toStruct();
        p.plugin = addressToUint128(address(plugin));
        _proposalId = p.fromStruct();

        uint32 openingTime = _proposalId.getStartTimestamp();
        vm.warp(openingTime + 1);

        // mock fn
        receiver.setAggregateVotes(_proposalId, _votes);

        vm.expectEmit(false, false, false, true);
        emit SubmitVoteSuccess(_proposalId, address(plugin), _votes);
        receiver.submitVotes(_proposalId);
    }
}
