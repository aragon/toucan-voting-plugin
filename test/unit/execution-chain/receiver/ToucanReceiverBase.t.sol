// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanReceiverEvents} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanProposal} from "@mocks/MockToucanVoting.sol";

import {deployToucanReceiver, deployMockToucanReceiver, deployMockToucanProposal} from "@utils/deployers.sol";

contract ToucanReceiverBaseTest is TestHelpers, IVoteContainer, IToucanReceiverEvents {
    GovernanceERC20 token;
    MockLzEndpointMinimal lzEndpoint;
    MockToucanReceiver receiver;
    DAO dao;
    MockToucanProposal plugin;

    function assertErrEq(ToucanReceiver.ErrReason e1, ToucanReceiver.ErrReason e2) internal pure {
        assertEq(uint(e1), uint(e2));
    }

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
        plugin = deployMockToucanProposal();
        receiver = deployMockToucanReceiver({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _votingPlugin: address(plugin)
        });
    }
}
