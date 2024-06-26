// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {Test} from "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverProposalIds is ToucanReceiverBaseTest {
    using ProposalIdCodec for uint256;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_invalidPlugin(uint256 _proposalSeed, uint32 _warpTo) public {
        // plugins are not validated here, only timestamps
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);

        // decode existing random proposal id
        address proposalPlugin = _proposalId.getPlugin();

        vm.assume(proposalPlugin != address(plugin));

        _warpToValidTs(_proposalId, _warpTo);
        assertTrue(receiver.isProposalOpen(_proposalId));

        bool valid = receiver.isProposalIdValid(_proposalId);
        assertFalse(valid);
    }

    function testFuzz_invalidProposalBeforeStart(uint256 _proposalId, uint32 _warpTo) public {
        // decode existing random proposal id
        uint32 startTs = _proposalId.getStartTimestamp();

        // set the plugin to the voting plugin
        receiver.setVotingPlugin(_proposalId.getPlugin());

        // assume that the startTs is greater than or equal the block ts we will move to
        vm.assume(startTs >= _warpTo);

        // warp to the start
        vm.warp(_warpTo);

        bool valid = receiver.isProposalIdValid({_proposalId: _proposalId});
        assertFalse(valid);
        assertFalse(receiver.isProposalOpen(_proposalId));
    }

    function testFuzz_invalidProposalAfterEnd(uint256 _proposalId, uint32 _warpTo) public {
        receiver.setVotingPlugin(_proposalId.getPlugin());
        // decode existing random proposal id
        uint32 _endTs = _proposalId.getEndTimestamp();

        // assume that the endTs is less than or equal the block ts we will move to
        vm.assume(_endTs <= _warpTo);

        // warp to the end
        vm.warp(_warpTo);

        bool valid = receiver.isProposalIdValid({_proposalId: _proposalId});
        assertFalse(valid);
        assertFalse(receiver.isProposalOpen(_proposalId));
    }

    // test proposal id is valid
    function testFuzz_validProposalId(uint256 _proposalSeed, uint32 _warpTo) public {
        uint _proposalId = _makeValidProposalIdFromSeed(_proposalSeed);
        receiver.setVotingPlugin(_proposalId.getPlugin());

        _warpToValidTs(_proposalId, _warpTo);
        assertTrue(receiver.isProposalOpen(_proposalId));

        bool valid = receiver.isProposalIdValid(_proposalId);
        assertTrue(valid);
    }

    // TODO: INTEGRATION, we should check this lines up with toucanVoting
}
