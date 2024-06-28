// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {ActionRelay, OptionsBuilder, MessagingFee} from "@execution-chain/crosschain/ActionRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockActionRelay} from "@mocks/MockActionRelay.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {deployActionRelay, deployMockActionRelay} from "@utils/deployers.sol";
import "@utils/converters.sol";

contract ActionRelayTest is TestHelpers, IVoteContainer {
    using OptionsBuilder for bytes;

    MockLzEndpointMinimal lzEndpoint;

    MockActionRelay relay;
    DAO dao;

    event ActionsRelayed(uint256 callId, uint256 destinationEid);

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});

        relay = deployMockActionRelay({_lzEndpoint: address(lzEndpoint), _dao: address(dao)});

        // set this address as the oapp admin for the relay
        dao.grant({
            _who: address(this),
            _where: address(relay),
            _permissionId: relay.OAPP_ADMINISTRATOR_ID()
        });
    }

    function test_cannotCallImpl() public {
        MockActionRelay impl = new MockActionRelay();
        vm.expectRevert(initializableError);
        impl.initialize(address(lzEndpoint), address(dao));
    }

    function test_cannotReinitialize() public {
        vm.expectRevert("Initializable: contract is already initialized");
        relay.initialize(address(lzEndpoint), address(dao));
    }

    function test_initialState() public view {
        assertEq(address(relay.dao()), address(dao));
        assertEq(address(relay.endpoint()), address(lzEndpoint));
    }

    function testFuzz_refundAddress(address _peer, uint32 _eid) public {
        relay.setPeer(_eid, addressToBytes32(_peer));
        assertEq(relay.refundAddress(_eid), _peer);
    }

    function testFuzz_quote(
        uint _proposalId,
        uint32 _dstEid,
        uint128 _gasLimit,
        IDAO.Action[] memory _actions,
        uint _allowFailureMap
    ) public view {
        ActionRelay.LzSendParams memory expectedParams = ActionRelay.LzSendParams({
            dstEid: _dstEid,
            gasLimit: _gasLimit,
            fee: MessagingFee(100, 0),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption({
                _gas: _gasLimit,
                _value: 0
            })
        });

        ActionRelay.LzSendParams memory params = relay.quote(
            _proposalId,
            _actions,
            _allowFailureMap,
            _dstEid,
            _gasLimit
        );

        assertEq(keccak256(abi.encode(params)), keccak256(abi.encode(expectedParams)));
    }

    function testFuzz_cannotCallRelayUnlessAuthorized(address _unauth, address _auth) public {
        vm.assume(_unauth != _auth);
        vm.assume(_auth != OSX_ANY_ADDR);

        dao.grant({
            _who: _auth,
            _where: address(relay),
            _permissionId: relay.XCHAIN_ACTION_RELAYER_ID()
        });

        bytes memory revertData = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(relay),
            _unauth,
            relay.XCHAIN_ACTION_RELAYER_ID()
        );

        ActionRelay.LzSendParams memory params;

        vm.expectRevert(revertData);
        vm.prank(_unauth);
        relay.relayActions(0, new IDAO.Action[](0), 0, params);
    }

    function testFuzz_emitsEventOnRelay(
        uint _proposalId,
        ActionRelay.LzSendParams memory _params,
        IDAO.Action[] memory _actions,
        uint _allowFailureMap,
        address _peerAddress
    ) public {
        vm.assume(_peerAddress != address(0));
        // force the fee to be 100 in native only
        _params.fee = MessagingFee(100, 0);
        relay.setPeer(_params.dstEid, addressToBytes32(_peerAddress));

        // give this address the relay permission
        dao.grant({
            _who: address(this),
            _where: address(relay),
            _permissionId: relay.XCHAIN_ACTION_RELAYER_ID()
        });

        vm.expectEmit(false, false, false, true);
        emit ActionsRelayed(_proposalId, _params.dstEid);
        relay.relayActions{value: 100}(_proposalId, _actions, _allowFailureMap, _params);

        // check the state sent was as expected
        MockActionRelay.LzSendReceived memory receipt = MockActionRelay(address(relay))
            .getLzSendReceived();

        assertEq(receipt.dstEid, _params.dstEid);
        assertEq(keccak256(abi.encode(receipt.fee)), keccak256(abi.encode(_params.fee)));
        assertEq(receipt.refundAddress, relay.refundAddress(_params.dstEid));
        assertEq(receipt.options, _params.options);

        bytes memory expectedMessage = abi.encode(_proposalId, _actions, _allowFailureMap);
        assertEq(keccak256(receipt.message), keccak256(expectedMessage));
    }

    function test_canUUPSUpgrade() public {
        address oldImplementation = relay.implementation();
        dao.grant({
            _who: address(this),
            _where: address(relay),
            _permissionId: relay.OAPP_ADMINISTRATOR_ID()
        });

        MockUpgradeTo newImplementation = new MockUpgradeTo();
        relay.upgradeTo(address(newImplementation));

        assertEq(relay.implementation(), address(newImplementation));
        assertNotEq(relay.implementation(), oldImplementation);
        assertEq(MockUpgradeTo(address(relay)).v2Upgraded(), true);
    }
}
