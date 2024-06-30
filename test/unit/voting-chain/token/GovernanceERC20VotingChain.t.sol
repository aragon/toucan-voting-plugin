// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {IERC20BurnableUpgradeable} from "@interfaces/IERC20BurnableUpgradeable.sol";
import {IERC20MintableUpgradeable} from "@interfaces/IERC20MintableUpgradeable.sol";
import {IERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanRelay} from "@mocks/MockToucanRelay.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {deployToucanRelay, deployMockToucanRelay} from "@utils/deployers.sol";

/// @dev single chain testing for the relay
contract TestGovERC20VotingChain is TestHelpers, IVoteContainer {
    GovernanceERC20VotingChain token;
    DAO dao;

    bytes4[] ifaces;

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);

        dao = createTestDAO({_initialOwner: address(this)});
        token = new GovernanceERC20VotingChain({
            _name: "Test Token",
            _symbol: "TT",
            _dao: IDAO(address(dao))
        });

        // for testing, grant mint permission to this contract
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });
    }

    function testFuzz_initialState(
        address _dao,
        string memory _name,
        string memory _symbol
    ) public {
        token = new GovernanceERC20VotingChain({_name: _name, _symbol: _symbol, _dao: IDAO(_dao)});
        assertEq(token.name(), _name);
        assertEq(token.symbol(), _symbol);
        assertEq(address(token.dao()), _dao);
        assertEq(token.totalSupply(), 0); // empty mint settings
    }

    function testFuzz_cannotBurnWithoutPermission(address _notBurner, address _burner) public {
        vm.assume(_notBurner != _burner);
        vm.assume(_burner != OSX_ANY_ADDR);

        dao.grant({
            _who: _burner,
            _where: address(token),
            _permissionId: token.BURN_PERMISSION_ID()
        });

        bytes memory revertData = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(token),
            _notBurner,
            token.BURN_PERMISSION_ID()
        );

        vm.expectRevert(revertData);
        vm.prank(_notBurner);
        token.burn(_notBurner, 1);
    }

    function testFuzz_canBurn(uint224 _mint, uint224 _burn, address _burner) public {
        vm.assume(_burner != OSX_ANY_ADDR);
        vm.assume(_burner != address(0));
        vm.assume(_mint > _burn);
        vm.assume(_burn > 0);

        address OTHER = address(1);

        dao.grant({
            _who: _burner,
            _where: address(token),
            _permissionId: token.BURN_PERMISSION_ID()
        });

        token.mint(_burner, _mint);

        assertEq(token.balanceOf(_burner), _mint);

        vm.startPrank(_burner);
        {
            token.burn(_burn);

            uint _remaining = _mint - _burn;

            assertEq(token.balanceOf(_burner), _remaining);
            assertEq(token.totalSupply(), _remaining);

            // send to another address
            token.transfer(OTHER, _remaining);

            // burn that too
            token.burn(OTHER, _remaining);
        }
        vm.stopPrank();

        assertEq(token.balanceOf(OTHER), 0);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(_burner), 0);
    }

    // static test for coverage
    function test_clockMode() public view {
        assertEq(
            keccak256(abi.encode(token.CLOCK_MODE())),
            keccak256(abi.encode("mode=timestamp"))
        );
    }

    function test_clock(uint48 _warp) public {
        vm.warp(_warp);
        assertEq(token.clock(), _warp);
    }

    function test_interface() public {
        ifaces.push(type(IERC20Upgradeable).interfaceId);
        ifaces.push(type(IERC20PermitUpgradeable).interfaceId);
        ifaces.push(type(IERC20MetadataUpgradeable).interfaceId);
        ifaces.push(type(IVotesUpgradeable).interfaceId);
        ifaces.push(type(IERC20MintableUpgradeable).interfaceId);
        ifaces.push(type(IERC20BurnableUpgradeable).interfaceId);

        for (uint i = 0; i < ifaces.length; i++) {
            assert(token.supportsInterface(ifaces[i]));
        }
    }
}
