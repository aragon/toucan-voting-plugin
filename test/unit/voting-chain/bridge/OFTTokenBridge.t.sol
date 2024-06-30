// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IOFT} from "@lz-oft/interfaces/IOFT.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockTokenBridge, OFTTokenBridge} from "@mocks/MockTokenBridge.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {deployTokenBridge, deployMockTokenBridge} from "@utils/deployers.sol";

/// @dev single chain testing for the relay
contract TestOFTTokenBridge is TestHelpers, IVoteContainer {
    GovernanceERC20VotingChain token;
    MockLzEndpointMinimal lzEndpoint;
    MockTokenBridge bridge;
    DAO dao;

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});
        token = new GovernanceERC20VotingChain({_name: "Test Token", _symbol: "TT", _dao: dao});

        // for testing, grant mint permission to this contract
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });

        bridge = deployMockTokenBridge({
            _token: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao)
        });

        // grant the bridge mint and burn permissions
        dao.grant({
            _who: address(bridge),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });

        dao.grant({
            _who: address(bridge),
            _where: address(token),
            _permissionId: token.BURN_PERMISSION_ID()
        });
    }

    function test_cannotCallImpl() public {
        OFTTokenBridge impl = new OFTTokenBridge();
        vm.expectRevert(initializableError);
        impl.initialize(address(token), address(lzEndpoint), address(dao));
    }

    function test_cannotReinitialize() public {
        vm.expectRevert(initializableError);
        bridge.initialize(address(token), address(lzEndpoint), address(dao));
    }

    function test_initialState() public view {
        (bytes4 interfaceId, uint64 version) = bridge.oftVersion();

        assertEq(interfaceId, type(IOFT).interfaceId);
        assertEq(version, 1);

        assertEq(bridge.token(), address(token));
        assertEq(address(bridge.dao()), address(dao));
        assertEq(bridge.approvalRequired(), true);
    }

    function testFuzz_debit(uint224 _amountLD, uint32 _dstEid) public {
        token.mint(address(this), _amountLD);

        uint256 balanceBefore = token.balanceOf(address(this));

        uint afterDust = bridge.previewRemoveDust(_amountLD);

        (uint256 sent, uint256 received) = bridge.debit({
            _amountLD: _amountLD,
            _minAmountLD: afterDust,
            _dstEid: _dstEid
        });

        uint256 balanceAfter = token.balanceOf(address(this));

        assertEq(balanceBefore - balanceAfter, afterDust);
        assertEq(sent, afterDust);
        assertEq(received, afterDust);
    }

    function testFuzz_credit(address _to, uint224 _amountLD, uint32 _srcEid) public {
        vm.assume(_to != address(0));

        uint256 received = bridge.credit({_to: _to, _amountLD: _amountLD, _srcEid: _srcEid});

        uint256 balanceAfter = token.balanceOf(_to);

        assertEq(balanceAfter, _amountLD);
        assertEq(received, _amountLD);
    }

    function test_canUUPSUpgrade() public {
        address oldImplementataion = bridge.implementation();
        dao.grant({
            _who: address(this),
            _where: address(bridge),
            _permissionId: bridge.OAPP_ADMINISTRATOR_ID()
        });
        MockUpgradeTo newImplementation = new MockUpgradeTo();
        bridge.upgradeTo(address(newImplementation));

        assertEq(bridge.implementation(), address(newImplementation));
        assertNotEq(bridge.implementation(), oldImplementataion);
        assertEq(MockUpgradeTo(address(bridge)).v2Upgraded(), true);
    }
}
