// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {DAO, createTestDAO, createTestDAORevertFallback, MockDAORevertFallback} from "@mocks/MockDAO.sol";
import {Sweeper, MockSweeper, MockSweeperUpgradeable} from "@mocks/MockSweeper.sol";
import {ProxyLib} from "@utils/deployers.sol";
import {MockERC20} from "@mocks/MockERC20.sol";

/// @dev single chain testing for the relay
contract TestSweeper is TestHelpers, IVoteContainer {
    MockSweeper public sweep;
    MockSweeperUpgradeable public sweepUp;
    DAO public dao;

    function _deployUpgradeable(address _dao) public returns (MockSweeperUpgradeable) {
        // deploy upgradeable version
        address base = address(new MockSweeperUpgradeable());
        bytes memory data = abi.encodeCall(MockSweeperUpgradeable.initialize, (_dao));
        address deployed = ProxyLib.deployUUPSProxy(base, data);
        return MockSweeperUpgradeable(payable(deployed));
    }

    function setUp() public {
        // deploy a DAO
        dao = createTestDAO(address(this));

        // deploy non-upgradeable version
        sweep = new MockSweeper(address(dao));

        // deploy upgradeable version
        sweepUp = _deployUpgradeable(address(dao));

        // grant sweep permission to this contract
        dao.grant(address(sweep), address(this), sweep.SWEEP_COLLECTOR_ID());
        dao.grant(address(sweepUp), address(this), sweepUp.SWEEP_COLLECTOR_ID());
    }

    // test sweepNative
    function testFuzz_sweepNative(uint256 _qty) public {
        vm.assume(_qty > 0);
        vm.assume(_qty < type(uint248).max); // overflow totalsupply
        vm.deal(address(this), 2 * _qty);

        // send $$ to the sweeper
        (bool ok, ) = address(sweep).call{value: _qty}("");
        assertTrue(ok, "transfer failed");
        (ok, ) = address(sweepUp).call{value: _qty}("");
        assertTrue(ok, "transfer upgradeable failed");

        sweep.sweepNative();

        assertEq(address(sweep).balance, 0);
        assertEq(address(dao).balance, _qty);

        sweepUp.sweepNative();

        assertEq(address(sweepUp).balance, 0);
        assertEq(address(dao).balance, _qty * 2);
    }

    // test sweepToken
    function testFuzz_sweepToken(uint256 _qty) public {
        vm.assume(_qty > 0);
        vm.assume(_qty < type(uint248).max); // overflow totalsupply

        MockERC20 token = new MockERC20();

        token.mint(address(sweep), _qty);
        token.mint(address(sweepUp), _qty);

        sweep.sweepToken(address(token));

        assertEq(token.balanceOf(address(sweep)), 0);
        assertEq(token.balanceOf(address(dao)), _qty);

        sweepUp.sweepToken(address(token));

        assertEq(token.balanceOf(address(sweepUp)), 0);
        assertEq(token.balanceOf(address(dao)), _qty * 2);
    }

    // test reverts nothing to refund if nothing to refund on native
    function test_nothingToRevertNative() public {
        bytes memory data = abi.encodeWithSelector(
            Sweeper.NothingToRefund.selector,
            address(0),
            address(dao)
        );

        vm.expectRevert(data);
        sweep.sweepNative();

        vm.expectRevert(data);
        sweepUp.sweepNative();
    }

    // test reverts notthing to refund if nothing to refund on token
    function test_nothingToRevertToken() public {
        MockERC20 token = new MockERC20();

        bytes memory data = abi.encodeWithSelector(
            Sweeper.NothingToRefund.selector,
            address(token),
            address(dao)
        );

        vm.expectRevert(data);
        sweep.sweepToken(address(token));

        vm.expectRevert(data);
        sweepUp.sweepToken(address(token));
    }

    // test refund failed if native refund fails (revert fallback on contract)
    function testFuzz_refundFailedNative(uint _qty) public {
        vm.deal(address(this), _qty);
        vm.assume(_qty / 2 > 0);

        MockDAORevertFallback daoRevert = new MockDAORevertFallback();

        bytes memory data = abi.encodeWithSelector(
            Sweeper.RefundFailed.selector,
            _qty / 2,
            address(0),
            address(daoRevert)
        );

        MockSweeper sweep_ = new MockSweeper(address(daoRevert));
        MockSweeperUpgradeable sweepUp_ = _deployUpgradeable(address(daoRevert));

        // send $$ to the sweeper
        payable(address(sweep_)).transfer(_qty / 2);
        payable(address(sweepUp_)).transfer(_qty / 2);

        vm.expectRevert(data);
        sweep_.sweepNative();

        vm.expectRevert(data);
        sweepUp_.sweepNative();
    }

    // test only sweep collector can sweep
    function testFuzz_onlyCollectorCanSweep(address _notThis) public {
        // we granted the permission to this contract
        vm.assume(_notThis != address(this));

        bytes memory data = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(sweep),
            _notThis,
            sweep.SWEEP_COLLECTOR_ID()
        );

        bytes memory dataUp = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(sweepUp),
            _notThis,
            sweepUp.SWEEP_COLLECTOR_ID()
        );

        address token = address(new MockERC20());

        vm.startPrank(_notThis);
        {
            vm.expectRevert(data);
            sweep.sweepNative();

            vm.expectRevert(data);
            sweep.sweepToken(token);

            vm.expectRevert(dataUp);
            sweepUp.sweepNative();

            vm.expectRevert(dataUp);
            sweepUp.sweepToken(token);
        }
        vm.stopPrank();
    }
}
