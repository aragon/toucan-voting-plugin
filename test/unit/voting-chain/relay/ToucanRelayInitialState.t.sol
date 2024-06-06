// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {deployToucanRelay} from "utils/deployers.sol";
import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";
import "@utils/deployers.sol";

import "forge-std/console2.sol";

/// @dev single chain testing for the relay
contract TestToucanRelayInitialState is ToucanRelayBaseTest {
    function setUp() public override {
        super.setUp();
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

    function testRevert_initializer() public {
        //     vm.expectRevert(IOAppCore.InvalidDelegate.selector);
        //     deployToucanRelay({_token: address(1), _lzEndpoint: address(lzEndpoint), _dao: address(0)});

        //     vm.expectRevert(ToucanRelay.InvalidToken.selector);
        //     deployToucanRelay({_token: address(0), _lzEndpoint: address(lzEndpoint), _dao: address(1)});

        //     // this reverts due to an internal call failing
        //     vm.expectRevert();
        //     deployToucanRelay({_token: address(1), _lzEndpoint: address(0), _dao: address(1)});
        console2.log("TODO");
    }
}
