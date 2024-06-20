// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

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

import {deployToucanReceiver, deployMockToucanReceiver} from "utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverInitialState is ToucanReceiverBaseTest {
    function setUp() public override {
        super.setUp();
    }

    // test the inital state is set including the events emitted
    function testFuzz_initializerReceiver(
        address _token,
        address _dao,
        address _votingPlugin,
        address _sender
    ) public {
        // checked by the OApp
        vm.assume(_dao != address(0));

        vm.expectEmit(false, false, false, true);
        emit NewVotingPluginSet(_votingPlugin, _sender);

        vm.startPrank(_sender);
        ToucanReceiver constructorReceiver = deployToucanReceiver({
            _governanceToken: _token,
            _lzEndpoint: address(lzEndpoint),
            _dao: _dao,
            _votingPlugin: _votingPlugin
        });
        vm.stopPrank();

        assertEq(address(constructorReceiver.governanceToken()), _token);
        assertEq(address(constructorReceiver.dao()), _dao);
        assertEq(address(constructorReceiver.endpoint()), address(lzEndpoint));
        assertEq(address(constructorReceiver.votingPlugin()), address(_votingPlugin));
    }

    // test we can set the voting plugin, but only if we have permission
    function testFuzz_cannotSetVotingPluginIfUnauthorized(
        address _votingPlugin,
        address _sender
    ) public {
        bytes memory revertData = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(receiver),
            _sender,
            receiver.RECEIVER_ADMIN_ID()
        );
        vm.expectRevert(revertData);
        vm.prank(_sender);
        receiver.setVotingPlugin(_votingPlugin);
    }

    function testFuzz_canSetVotingPluginIfAuthorized(
        address _votingPlugin,
        address _sender
    ) public {
        // this is not allowed by default in OSx
        vm.assume(_sender != OSX_ANY_ADDR);

        // we are allowed to set the voting plugin during shared setup
        vm.assume(_sender != address(this));

        dao.grant({
            _who: _sender,
            _where: address(receiver),
            _permissionId: receiver.RECEIVER_ADMIN_ID()
        });

        vm.expectEmit(false, false, false, true);
        emit NewVotingPluginSet(_votingPlugin, _sender);

        vm.prank(_sender);
        receiver.setVotingPlugin(_votingPlugin);

        vm.assume(address(receiver.votingPlugin()) == _votingPlugin);
    }

    function testFuzz_testFetchingProposalBlockSnapshot(
        uint _proposalId,
        uint64 _blockSnapshot
    ) public {
        plugin.setSnapshotBlock(_proposalId, _blockSnapshot);
        assertEq(receiver.getProposalBlockSnapshot(_proposalId), _blockSnapshot);
    }
}
