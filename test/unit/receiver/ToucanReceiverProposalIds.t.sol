// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {GovernanceERC20} from "src/token/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "src/crosschain/toucanRelay/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {Test} from "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverProposalIds is ToucanReceiverBaseTest {
    using ProposalIdCodec for uint256;

    function setUp() public override {
        super.setUp();
    }

    function testFuzz_invalidPlugin(uint256 _proposalId, uint _warpTo) public {
        // decode existing random proposal id
        // address proposalPlugin = _proposalId.getPlugin();
        (, uint32 _startTs, uint32 _endTs, ) = ProposalIdCodec.decode(_proposalId);

        // assume that the startTs is less than the block ts we will move to
        vm.assume(_warpTo > _startTs);

        // assume that the endTs is greater than the block ts we will move to
        vm.assume(_warpTo < _endTs);
        // assume that the plugin is not equal to the voting plugin
        // vm.assume(proposalPlugin != address(plugin));

        // _warpToValidTs(_proposalId, _warpTo);

        // bool valid = receiver.isProposalIdValid(_proposalId);
        // assertFalse(valid);
    }

    // function testFuzz_invalidProposalBeforeStart(uint256 _proposalId, uint32 _warpTo) public {
    //     // decode existing random proposal id
    //     uint32 startTs = _proposalId.getStartTimestamp();

    //     // assume that the startTs is greater than or equal the block ts we will move to
    //     vm.assume(startTs >= _warpTo);

    //     // warp to the start
    //     vm.warp(_warpTo);

    //     bool valid = receiver.isProposalIdValid({_proposalId: _proposalId});
    //     assertFalse(valid);
    // }

    // function testFuzz_invalidProposalAfterEnd(uint256 _proposalId, uint32 _warpTo) public {
    //     // decode existing random proposal id
    //     uint32 _endTs = _proposalId.getEndTimestamp();

    //     // assume that the endTs is less than or equal the block ts we will move to
    //     vm.assume(_endTs <= _warpTo);

    //     // warp to the end
    //     vm.warp(_warpTo);

    //     bool valid = receiver.isProposalIdValid({_proposalId: _proposalId});
    //     assertFalse(valid);
    // }
    // test proposal id is valid
    // plugin must equal the voting plugin
    // timestamp must > start Ts
    // timestamp must < end Ts
    // INTEGRATION, we should check this lines up with toucanVoting
    // otherwise it's considered true
}
