// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "src/token/governance/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {Test} from "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanRelay} from "@mocks/MockToucanRelay.sol";

import {deployToucanRelay, deployMockToucanRelay} from "utils/deployers.sol";

/// @dev single chain testing for the relay
contract ToucanRelayBaseTest is Test, IVoteContainer {
    GovernanceERC20VotingChain token;
    MockLzEndpointMinimal lzEndpoint;
    MockToucanRelay relay;
    DAO dao;

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
    }

    // test the refund address before and after setting peers and with eid combos

    // test the chainId and with an override

    // test getVotes: should update correctly for execution chain id, proposal id and voter

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- HELPERS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~

    function _warpToValidTs(uint256 _proposalId, uint256 _warpTo) internal {
        (, uint32 _startTs, uint32 _endTs) = ProposalIdCodec.decode(_proposalId);

        // assume that the startTs is less than the block ts we will move to
        vm.assume(_startTs < _warpTo);

        // assume that the endTs is greater than the block ts we will move to
        vm.assume(_endTs > _warpTo);

        vm.warp(_warpTo);
    }
}
