// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanRelay} from "@mocks/MockToucanRelay.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {deployToucanRelay, deployMockToucanRelay} from "@utils/deployers.sol";

/// @dev single chain testing for the relay
contract ToucanRelayBaseTest is TestHelpers, IVoteContainer {
    GovernanceERC20VotingChain token;
    MockLzEndpointMinimal lzEndpoint;
    MockToucanRelay relay;
    DAO dao;

    /// @notice Emitted when a voter successfully casts a vote on a proposal.
    event VoteCast(
        uint32 indexed dstEid,
        uint256 indexed proposalRef,
        address indexed voter,
        Tally voteOptions
    );

    /// @notice Emitted when anyone dispatches the votes for a proposal to the execution chain.
    event VotesDispatched(
        uint32 indexed dstEid,
        uint256 indexed proposalRef,
        Tally votes,
        MessagingReceipt receipt
    );

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});
        token = new GovernanceERC20VotingChain({_name: "Test Token", _symbol: "TT", _dao: dao});

        // for testing, grant mint permission to this contract
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });

        relay = deployMockToucanRelay({
            _token: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _dstEid: 1,
            _buffer: 0
        });

        // set this address as the oapp admin for the relay
        dao.grant({
            _who: address(this),
            _where: address(relay),
            _permissionId: relay.OAPP_ADMINISTRATOR_ID()
        });
    }

    function assertErrEq(ToucanRelay.ErrReason e1, ToucanRelay.ErrReason e2) internal pure {
        assertEq(uint(e1), uint(e2));
    }
}
