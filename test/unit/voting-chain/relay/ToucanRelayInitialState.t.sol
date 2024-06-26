// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {deployToucanRelay} from "@utils/deployers.sol";
import "@utils/converters.sol";
import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import "forge-std/console2.sol";

/// @dev single chain testing for the relay
contract TestToucanRelayInitialState is ToucanRelayBaseTest {
    function setUp() public override {
        super.setUp();
    }

    // TODO reentrancy gov token

    function test_cannotCallImplementation() public {
        ToucanRelay impl = new ToucanRelay();
        vm.expectRevert(initializableError);
        impl.initialize(address(0), address(lzEndpoint), address(dao));
    }

    function testFuzz_initializer(address _token, address _dao) public {
        // dao is checked by OApp
        vm.assume(_dao != address(0));

        // token is checked by the relay
        vm.assume(_token != address(0));

        ToucanRelay constructorRelay = deployToucanRelay({
            _token: _token,
            _lzEndpoint: address(lzEndpoint),
            _dao: _dao
        });

        assertEq(address(constructorRelay.token()), _token);
        assertEq(address(constructorRelay.dao()), _dao);
        assertEq(address(constructorRelay.endpoint()), address(lzEndpoint));
    }

    function testRevert_initializer(address _dao) public {
        vm.assume(_dao != address(0));
        address impl = address(new ToucanRelay());
        bytes memory data = abi.encodeCall(
            ToucanRelay.initialize,
            (address(0), address(lzEndpoint), _dao)
        );

        vm.expectRevert(abi.encodeWithSelector(ToucanRelay.InvalidToken.selector));
        ProxyLib.deployUUPSProxy(impl, data);
    }

    function test_chainId() public view {
        assertEq(relay.chainId(), block.chainid);
    }

    function testFuzz_refundAddress(address _peer, uint32 _eid) public {
        relay.setPeer(_eid, addressToBytes32(_peer));
        assertEq(relay.refundAddress(_eid), _peer);
    }

    function test_receiveReverts() public {
        bytes memory revertData = abi.encodeWithSelector(ToucanRelay.CannotReceive.selector);
        vm.expectRevert(revertData);
        Origin memory o;
        relay._lzReceive(new bytes(0), o, new bytes(0));
    }
}
