// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockOFTUpgradeable, MockOAppUpgradeable, MockOFT, MockOApp} from "@mocks/MockOApp.sol";

import {deployMockOApp, deployMockOFT} from "@utils/deployers.sol";

import {OAppBaseTest} from "./OAppBase.t.sol";

contract OAppInitializerTest is OAppBaseTest {
    function setUp() public virtual override {
        super.setUp();
    }

    // test the initializer contract
}
