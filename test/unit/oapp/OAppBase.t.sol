// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockOFTUpgradeable, MockOAppUpgradeable, MockOFT, MockOApp} from "@mocks/MockOApp.sol";

import {deployMockOApp, deployMockOFT} from "@utils/deployers.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";

contract OAppBaseTest is TestHelpers, IVoteContainer {
    MockLzEndpointMinimal lzEndpoint;
    DAO dao;

    MockOFT layerZeroOFT;
    MockOApp layerZeroOApp;

    MockOFTUpgradeable aragonOFT;
    MockOAppUpgradeable aragonOApp;

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});

        layerZeroOFT = new MockOFT("layerZeroOFT", "lOFT", address(lzEndpoint), address(dao));
        layerZeroOApp = new MockOApp(address(lzEndpoint), address(dao));

        aragonOFT = deployMockOFT("aragonOFT", "aOFT", address(lzEndpoint), address(dao));
        aragonOApp = deployMockOApp(address(lzEndpoint), address(dao));
    }

    // test the initializer contract

    // test all functions that revert on the vanilla OApp as ownable revert with DaoAuthorizable

    // test that the delegate is the DAO
}
