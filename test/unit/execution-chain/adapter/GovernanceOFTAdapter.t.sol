// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "@mocks/MockToucanVoting.sol";

import {deployGovernanceOFTAdapter} from "utils/deployers.sol";

/// @dev single chain testing for the relay
contract TestGovernanceOFTAdapter is TestHelpers, IVoteContainer {
    GovernanceERC20 token;
    MockLzEndpointMinimal lzEndpoint;
    GovernanceOFTAdapter adapter;
    DAO dao;

    function setUp() public virtual {
        // reset timestamps and blocks
        vm.warp(0);
        vm.roll(0);
        lzEndpoint = new MockLzEndpointMinimal();
        dao = createTestDAO({_initialOwner: address(this)});
        GovernanceERC20.MintSettings memory emptyMintSettings = GovernanceERC20.MintSettings(
            new address[](0),
            new uint256[](0)
        );
        token = new GovernanceERC20({
            _name: "Test Token",
            _symbol: "TT",
            _dao: dao,
            _mintSettings: emptyMintSettings
        });

        adapter = deployGovernanceOFTAdapter({
            _token: address(token),
            _voteProxy: address(this),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao)
        });
    }

    function test_delegateConstructor(address _voteProxy) public {
        GovernanceOFTAdapter adapter_ = deployGovernanceOFTAdapter({
            _token: address(token),
            _voteProxy: _voteProxy,
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao)
        });

        assertEq(token.delegates(address(adapter_)), _voteProxy);
    }

    function test_initialState() public view {
        assertEq(adapter.token(), address(token));
        assertEq(address(adapter.endpoint()), address(lzEndpoint));
        assertEq(address(adapter.dao()), address(dao));
        assertEq(token.delegates(address(adapter)), address(this));
    }

    function testFuzz_cannotChangeDelegationWithoutPermission(address _attacker) public {
        bytes memory revertData = abi.encodeWithSelector(
            DaoUnauthorized.selector,
            address(dao),
            address(adapter),
            _attacker,
            adapter.SET_CROSSCHAIN_DELEGATE_ID()
        );
        vm.expectRevert(revertData);
        vm.prank(_attacker);
        adapter.delegate(_attacker);
    }

    function testFuzz_daoCanGrantDelegate(address _newDelegate, address _admin) public {
        vm.assume(_admin != OSX_ANY_ADDR);

        dao.grant({
            _who: _admin,
            _where: address(adapter),
            _permissionId: adapter.SET_CROSSCHAIN_DELEGATE_ID()
        });

        if (_newDelegate == address(this)) {
            assertEq(token.delegates(address(adapter)), _newDelegate);
        } else {
            assertFalse(token.delegates(address(adapter)) == _newDelegate);
        }

        vm.prank(_admin);
        adapter.delegate(_newDelegate);

        assertEq(token.delegates(address(adapter)), _newDelegate);
    }
}
