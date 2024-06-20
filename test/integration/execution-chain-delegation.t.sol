// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

/// Aragon contracts
// OSx
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

// project
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";

/// test imports
import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {MockDAOSimplePermission as MockDAO} from "@mocks/MockDAO.sol";
import "@utils/deployers.sol";

/**
 * Tests a mock version of using a delegation mechanism to allow votes held on Chain B to be used on Chain A.
 * The mechanism is pretty straightforward, we are only testing chain A:
 * - Contract X "MockOFTAdapter" will delegate votes to a contract Y "MockReceiver" on Chain A.
 * - User transfers votes to X, we assume this causes a bridge transfer to Chain B but we don't test that here.
 * - We check to ensure the delegated votes are correctly accounted for in the voting power of the receiver contract Y.
 * - We do a quick vote to ensure the delegated votes are correctly accounted for in the voting power of the receiver contract Y.
 */
contract TestExecutionChainDelegation is Test {
    GovernanceERC20 public token;
    GovernanceOFTAdapter public adapter;
    MockLzEndpointMinimal public lzEndpoint;
    ToucanReceiver public receiver;
    IDAO public dao;

    function setUp() public {
        // deploy the lzEndpoint
        lzEndpoint = new MockLzEndpointMinimal();

        // create a mock dao with no permissions
        dao = IDAO(address(new MockDAO()));

        // instantiate the governance token with 100 tokens minted to this address
        address[] memory receivers = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        receivers[0] = address(this);
        amounts[0] = 100 ether;
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            receivers,
            amounts
        );
        token = new GovernanceERC20(dao, "TestToken", "TT", mintSettings);

        // deploy the adapter with no voteProxy, we can set it in the next tx
        adapter = deployGovernanceOFTAdapter({
            _token: address(token),
            _voteProxy: address(0),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao)
        });

        // deploy the receiver contract
        receiver = deployToucanReceiver({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(this),
            _votingPlugin: address(0)
        });

        // delegate votes to the receiver contract
        adapter.delegate(address(receiver));
    }

    // test that the voting power of the receiver is correctly updated
    // when tokens are sent to the adapter
    function test_delegatedBalanceUpdatesCorrectly() public {
        assertEq(token.balanceOf(address(this)), 100 ether, "balance should be 100");

        // first we check the voting power of this contract
        assertEq(
            token.getVotes(address(this)),
            100 ether,
            "governance_erc20 should have automatically self delegated"
        );

        // transfer 10 tokens to the adapter
        // note this would be irrecoverable if done in reality
        token.transfer(address(adapter), 10 ether);

        // the receiver's voting power should be updated in the next block
        vm.roll(block.number + 1);

        // check the voting power of the receiver
        assertEq(token.getVotes(address(receiver)), 10 ether, "receiver should have 10 votes");
    }
}
