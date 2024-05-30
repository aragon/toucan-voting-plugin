// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20} from "src/token/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanReceiverEvents} from "src/crosschain/toucanRelay/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "@mocks/MockToucanVoting.sol";

import {deployToucanReceiver, deployMockToucanReceiver, deployMockToucanVoting} from "utils/deployers.sol";

/// @dev single chain testing for the relay
contract ToucanReceiverBaseTest is TestHelpers, IVoteContainer, IToucanReceiverEvents {
    GovernanceERC20 token;
    MockLzEndpointMinimal lzEndpoint;
    MockToucanReceiver receiver;
    DAO dao;
    MockToucanVoting plugin;

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);
        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});
        GovernanceERC20.MintSettings memory emptyMintSettings = GovernanceERC20.MintSettings(
            new address[](0),
            new uint256[](0)
        );
        token = new GovernanceERC20({
            _name: "Test Token",
            _symbol: "TT",
            _dao: dao,
            _mintSettings: emptyMintSettings
        });
        // for testing, grant mint permission to this contract
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });
        plugin = deployMockToucanVoting();
        receiver = deployMockToucanReceiver({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _votingPlugin: address(plugin)
        });
        // grant this contract the ability to manage the receiver
        dao.grant({
            _who: address(this),
            _where: address(receiver),
            _permissionId: receiver.RECEIVER_ADMIN_ID()
        });
    }

    // test is current delegate

    // test the sweeper
}
