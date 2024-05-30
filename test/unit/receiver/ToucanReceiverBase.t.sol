// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20} from "src/token/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanReceiverEvents} from "src/crosschain/toucanRelay/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "@mocks/MockToucanVoting.sol";

import {deployToucanReceiver, deployMockToucanReceiver, deployMockToucanVoting} from "utils/deployers.sol";

/// @dev single chain testing for the relay
contract ToucanReceiverBaseTest is TestHelpers, IVoteContainer, IToucanReceiverEvents {
    GovernanceERC20 token;
    MockLzEndpointMinimal lzEndpoint;
    MockToucanReceiver receiver;
    DAO dao;
    MockToucanVoting plugin;

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

        // for testing, grant mint permission to this contract
        dao.grant({
            _who: address(this),
            _where: address(token),
            _permissionId: token.MINT_PERMISSION_ID()
        });

        plugin = deployMockToucanVoting();

        receiver = deployMockToucanReceiver({
            _governanceToken: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao),
            _votingPlugin: address(plugin)
        });
    }

    // test the inital state is set including the events emitted

    // test we can set the voting plugin, but only if we have permission

    // test proposal id is valid
    // plugin must equal the voting plugin
    // timestamp must > start Ts
    // timestamp must < end Ts
    // INTEGRATION, we should check this lines up with toucanVoting
    // otherwise it's considered true

    // test has enough voting power
    // if snapshot block is zero, false
    // if no voting power at block false
    // if lt voting power at block false
    // if gte voting power at block true
    // if gte voting power at block inc transfer true
    // if gte voting power at block but not enough delegated false
    // if gte voting power at block but not enough delegated inc transfer true

    // test receive votes
    // from fresh
    // from stateful, single voting chain
    // from stateful, single proposal id
    // from stateful, combo
    // event emitted

    // test is current delegate

    // test the sweeper

    //  test submit votes
    // reverts on invalid proposal and throws error
    // reverts if nothing to submit
    // reverts if wrong proposal id ergo nothing to submit
    // calls the vote function with the expected values
    // emits the event

    // test lzReceive
    // reverts with invalid proposal ID
    // reverts with insufficient delegated voting power
    // stores the votes if submitVotes fails and emits the event

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- HELPERS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~
}
