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
contract TestToucanReceiverInitialState is ToucanReceiverBaseTest {
    address constant OSX_ANY_ADDR = address(type(uint160).max);

    function setUp() public override {
        super.setUp();
    }

    // test the inital state is set including the events emitted
    function testFuzz_constructor(
        address _token,
        address _dao,
        address _votingPlugin,
        address _sender
    ) public {
        // checked by the OApp
        vm.assume(_dao != address(0));

        vm.expectEmit(false, false, false, true);
        emit NewVotingPluginSet(_votingPlugin, _sender);

        vm.prank(_sender);
        ToucanReceiver constructorReceiver = deployToucanReceiver({
            _governanceToken: _token,
            _lzEndpoint: address(lzEndpoint),
            _dao: _dao,
            _votingPlugin: _votingPlugin
        });

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
}
