// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "src/token/governance/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {deployToucanRelay} from "utils/deployers.sol";
import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanRelayInitialState is ToucanRelayBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testFuzz_constructor(address _token, address _dao) public {
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

    function testRevert_constructor() public {
        vm.expectRevert(IOAppCore.InvalidDelegate.selector);
        new ToucanRelay({_token: address(1), _lzEndpoint: address(lzEndpoint), _dao: address(0)});

        vm.expectRevert(ToucanRelay.InvalidToken.selector);
        new ToucanRelay({_token: address(0), _lzEndpoint: address(lzEndpoint), _dao: address(1)});

        // this reverts due to an internal call failing
        vm.expectRevert();
        new ToucanRelay({_token: address(1), _lzEndpoint: address(0), _dao: address(1)});
    }
}
