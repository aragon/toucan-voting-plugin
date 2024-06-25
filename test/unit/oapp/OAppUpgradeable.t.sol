// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {EnforcedOptionParam} from "@lz-oapp/interfaces/IOAppOptionsType3.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockOFTUpgradeable, MockOAppUpgradeable, MockOFT, MockOApp} from "@mocks/MockOApp.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {deployMockOApp, deployMockOFT} from "@utils/deployers.sol";

import {OAppBaseTest} from "./OAppBase.t.sol";

import "@utils/converters.sol";

contract OAppTest is OAppBaseTest {
    function testFuzz_ownableRevertWithDaoAuthorizable(
        address _notAuthorized,
        address _authorized
    ) public {
        vm.assume(_notAuthorized != _authorized);
        vm.assume(_notAuthorized != address(this));
        vm.assume(_authorized != OSX_ANY_ADDR);
        vm.assume(_authorized != address(0));

        dao.grant({
            _who: _authorized,
            _where: address(aragonOApp),
            _permissionId: aragonOApp.OAPP_ADMINISTRATOR_ID()
        });

        bytes memory expectedError = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(aragonOApp),
            _notAuthorized,
            aragonOApp.OAPP_ADMINISTRATOR_ID()
        );

        bytes32 na = addressToBytes32(_notAuthorized);

        vm.startPrank(_notAuthorized);
        {
            vm.expectRevert(ownableError);
            layerZeroOApp.setDelegate(_notAuthorized);

            vm.expectRevert(ownableError);
            layerZeroOApp.setPeer(1, na);

            vm.expectRevert(expectedError);
            aragonOApp.setDelegate(_notAuthorized);

            vm.expectRevert(expectedError);
            aragonOApp.setPeer(1, na);
        }

        vm.stopPrank();
    }

    function testFuzz_oftOwnableRevertWithDaoAuthorizable(
        address _notAuthorized,
        address _authorized
    ) public {
        vm.assume(_notAuthorized != _authorized);
        vm.assume(_notAuthorized != address(this));
        vm.assume(_authorized != OSX_ANY_ADDR);
        vm.assume(_authorized != address(0));

        dao.grant({
            _who: _authorized,
            _where: address(aragonOFT),
            _permissionId: aragonOFT.OAPP_ADMINISTRATOR_ID()
        });

        bytes memory expectedError = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(aragonOFT),
            _notAuthorized,
            aragonOFT.OAPP_ADMINISTRATOR_ID()
        );

        EnforcedOptionParam[] memory enforcedOptions;

        vm.startPrank(_notAuthorized);
        {
            vm.expectRevert(ownableError);
            layerZeroOFT.setMsgInspector(_notAuthorized);

            vm.expectRevert(ownableError);
            layerZeroOFT.setPreCrime(_notAuthorized);

            vm.expectRevert(ownableError);
            layerZeroOFT.setEnforcedOptions(enforcedOptions);

            vm.expectRevert(expectedError);
            aragonOFT.setMsgInspector(_notAuthorized);

            vm.expectRevert(expectedError);
            aragonOFT.setPreCrime(_notAuthorized);

            vm.expectRevert(expectedError);
            aragonOFT.setEnforcedOptions(enforcedOptions);
        }

        vm.stopPrank();
    }
}
