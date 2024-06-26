// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

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

    event VotesDispatched(uint256 indexed proposalId, Tally votes);
    event VoteCast(uint256 indexed proposalId, address voter, Tally voteOptions);

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
            _dao: address(dao)
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
