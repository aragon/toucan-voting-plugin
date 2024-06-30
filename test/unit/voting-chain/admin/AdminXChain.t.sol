// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IOAppReceiver} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IPlugin} from "@aragon/osx/core/plugin/IPlugin.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";

import {OAppReceiverUpgradeable} from "@oapp-upgradeable/aragon-oapp/OAppReceiverUpgradeable.sol";
import {AdminXChain, Origin} from "@voting-chain/crosschain/AdminXChain.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {deployAdminXChain} from "@utils/deployers.sol";
import "@utils/converters.sol";

contract AdminXChainTest is TestHelpers, IVoteContainer {
    MockLzEndpointMinimal lzEndpoint;
    AdminXChain admin;
    DAO dao;

    event XChainExecuted(
        uint proposalId,
        uint256 foreignCallId,
        uint32 srcEid,
        address sender,
        uint256 failureMap
    );

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});

        admin = deployAdminXChain({_lzEndpoint: address(lzEndpoint), _dao: address(dao)});

        // set this address as the oapp admin for the relay
        dao.grant({
            _who: address(this),
            _where: address(admin),
            _permissionId: admin.OAPP_ADMINISTRATOR_ID()
        });
    }

    function test_cannotCallImpl() public {
        AdminXChain impl = new AdminXChain();
        vm.expectRevert(initializableError);
        impl.initialize(address(lzEndpoint), address(dao));
    }

    function test_cannotReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        admin.initialize(address(lzEndpoint), address(dao));
    }

    function test_initialState() public view {
        assertEq(address(admin.dao()), address(dao));
        assertEq(address(admin.endpoint()), address(lzEndpoint));
    }

    function test_supportsInterface() public view {
        assert(admin.supportsInterface(type(IPlugin).interfaceId));
        assert(admin.supportsInterface(type(IProposal).interfaceId));
        assert(admin.supportsInterface(type(IOAppReceiver).interfaceId));
    }

    function testFuzz_cannotCallWithoutSetupAndInstallation(
        uint32 _eid,
        bytes32 _peer,
        Origin memory _origin,
        bytes32 _guid,
        address _executor,
        bytes memory _extraData,
        address _sender
    ) public {
        vm.assume(_sender != address(lzEndpoint));
        vm.assume(_origin.srcEid != _eid);
        vm.assume(_origin.sender != _peer);

        // encode a simple message
        bytes memory _message = abi.encode(0, new IDAO.Action[](0), 0);

        // revert 1 if the sender is not the endpoint
        vm.expectRevert(
            abi.encodeWithSelector(OAppReceiverUpgradeable.OnlyEndpoint.selector, _sender)
        );
        vm.prank(_sender);
        admin.lzReceive(_origin, _guid, _message, _executor, _extraData);

        // set the peer
        admin.setPeer(_eid, _peer);

        // revert 2 if the peer is not set (eid and srcEid are different)
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, _origin.srcEid));
        vm.prank(address(lzEndpoint));
        admin.lzReceive(_origin, _guid, _message, _executor, _extraData);

        // ensure the peer is correct
        _origin.srcEid = _eid;

        // revert 3 peer is incorrect
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.OnlyPeer.selector, _eid, _origin.sender));
        vm.prank(address(lzEndpoint));
        admin.lzReceive(_origin, _guid, _message, _executor, _extraData);

        // should not revert if the peer is correct
        // but will revert on the DAO as not installed
        _origin.sender = _peer;

        vm.expectRevert(
            abi.encodeWithSelector(
                PermissionManager.Unauthorized.selector,
                address(dao),
                address(admin),
                dao.EXECUTE_PERMISSION_ID()
            )
        );
        vm.prank(address(lzEndpoint));
        admin.lzReceive(_origin, _guid, _message, _executor, _extraData);
    }

    // executes the action, emits the event and stores the proposal
    function testFuzz_executesProposal(bytes32 _peer, uint32 _eid, uint256 _callId) public {
        address luckyBoi = address(69420);
        address scrub = address(0x105e7);

        // set the peer
        admin.setPeer(_eid, _peer);

        // install the plugin by granting execute on the DAO
        dao.grant({
            _who: address(admin),
            _where: address(dao),
            _permissionId: dao.EXECUTE_PERMISSION_ID()
        });

        // encode an action to transfer 1 eth to a random user:
        // encode a second action but we will allow it to fail
        vm.deal(address(dao), 2 ether);

        IDAO.Action[] memory actions = new IDAO.Action[](2);
        actions[0] = IDAO.Action({to: luckyBoi, data: "", value: 1 ether});

        // too much ether so will fail
        actions[1] = IDAO.Action({to: scrub, data: "", value: 1.5 ether});

        uint256 allowFailureMap = 1 << 1;

        // encode the message
        bytes memory _message = abi.encode(_callId, actions, allowFailureMap);

        // send the message
        Origin memory _origin = Origin({srcEid: _eid, sender: _peer, nonce: 0});

        vm.prank(address(lzEndpoint));
        vm.expectEmit(false, false, false, true);
        emit XChainExecuted(0, _callId, _eid, bytes32ToAddress(_peer), 1 << 1);
        admin.lzReceive(_origin, bytes32(0), _message, address(0), "");

        // check balances
        assertEq(luckyBoi.balance, 1 ether);
        assertEq(scrub.balance, 0);

        // sending again should increment proposal id but with a new timestamp
        vm.warp(100);
        vm.prank(address(lzEndpoint));
        vm.expectEmit(false, false, false, true);
        emit XChainExecuted(1, _callId, _eid, bytes32ToAddress(_peer), 1 << 1);
        admin.lzReceive(_origin, bytes32(0), _message, address(0), "");

        // check balances
        assertEq(luckyBoi.balance, 2 ether);
        assertEq(scrub.balance, 0);

        // check the state
        assertEq(admin.xChainActionMetadata(0).callId, _callId);
        assertEq(admin.xChainActionMetadata(1).callId, _callId);

        assertEq(admin.xChainActionMetadata(0).received, 0);
        assertEq(admin.xChainActionMetadata(1).received, 100);
    }

    function test_canUUPSUpgrade() public {
        address oldImplementation = admin.implementation();
        MockUpgradeTo newImplementation = new MockUpgradeTo();
        admin.upgradeTo(address(newImplementation));

        assertEq(admin.implementation(), address(newImplementation));
        assertNotEq(admin.implementation(), oldImplementation);
        assertEq(MockUpgradeTo(address(admin)).v2Upgraded(), true);
    }
}
