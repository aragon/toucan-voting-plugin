// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IToucanVoting} from "@toucan-voting/ToucanVoting.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder, ProposalReference} from "@libs/ProposalRefEncoder.sol";

import {Test} from "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {MockUpgradeTo} from "@mocks/MockUpgradeTo.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";

import {deployToucanReceiver, deployMockToucanReceiver} from "@utils/deployers.sol";
import {ToucanReceiverBaseTest} from "./ToucanReceiverBase.t.sol";

/// @dev single chain testing for the relay
contract TestToucanReceiverProposalRef is ToucanReceiverBaseTest {
    using ProposalRefEncoder for uint256;

    function setUp() public override {
        super.setUp();

        dao.grant({
            _who: address(this),
            _where: address(receiver),
            _permissionId: receiver.OAPP_ADMINISTRATOR_ID()
        });
    }

    // proposal ref invalid if any of the fields mismatch
    function testFuzz_refInvalidIfMissingFields(
        uint32 _proposalId,
        uint32 _startTs,
        uint32 _endTs,
        uint32 _blockTs
    ) public {
        vm.assume(_startTs > 0 || _endTs > 0 || _blockTs > 0);

        plugin.setParameters(
            _proposalId,
            IToucanVoting.ProposalParameters({
                votingMode: IToucanVoting.VotingMode.VoteReplacement,
                supportThreshold: 0,
                startDate: _startTs,
                endDate: _endTs,
                snapshotBlock: _blockTs,
                snapshotTimestamp: 0,
                minVotingPower: 0
            })
        );

        // 1. should be valid base case
        assertTrue(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: _proposalId,
                    _plugin: address(plugin),
                    _proposalStartTimestamp: _startTs,
                    _proposalEndTimestamp: _endTs,
                    _proposalBlockSnapshotTimestamp: _blockTs
                })
            ),
            "valid ref"
        );

        // 2. should be invalid if proposalId is wrong
        assertFalse(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: uint32(uint256(keccak256(abi.encode(_proposalId)))),
                    _plugin: address(plugin),
                    _proposalStartTimestamp: _startTs,
                    _proposalEndTimestamp: _endTs,
                    _proposalBlockSnapshotTimestamp: _blockTs
                })
            ),
            "invalid ref - proposalId"
        );

        // 3. should be invalid if plugin is wrong
        assertFalse(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: _proposalId,
                    _plugin: address(uint160(uint256(keccak256(abi.encode(address(plugin)))))),
                    _proposalStartTimestamp: _startTs,
                    _proposalEndTimestamp: _endTs,
                    _proposalBlockSnapshotTimestamp: _blockTs
                })
            ),
            "invalid ref - plugin"
        );

        // 4. should be invalid if startTs is wrong
        assertFalse(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: _proposalId,
                    _plugin: address(plugin),
                    _proposalStartTimestamp: uint32(uint256(keccak256(abi.encode(_startTs)))),
                    _proposalEndTimestamp: _endTs,
                    _proposalBlockSnapshotTimestamp: _blockTs
                })
            ),
            "invalid ref - startTs"
        );

        // 5. should be invalid if endTs is wrong
        assertFalse(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: _proposalId,
                    _plugin: address(plugin),
                    _proposalStartTimestamp: _startTs,
                    _proposalEndTimestamp: uint32(uint256(keccak256(abi.encode(_endTs)))),
                    _proposalBlockSnapshotTimestamp: _blockTs
                })
            ),
            "invalid ref - endTs"
        );

        // 6. should be invalid if blockTs is wrong
        assertFalse(
            receiver.isProposalRefValid(
                ProposalRefEncoder.encode({
                    _proposalId: _proposalId,
                    _plugin: address(plugin),
                    _proposalStartTimestamp: _startTs,
                    _proposalEndTimestamp: _endTs,
                    _proposalBlockSnapshotTimestamp: uint32(
                        uint256(keccak256(abi.encode(_blockTs)))
                    )
                })
            ),
            "invalid ref - blockTs"
        );
    }
}
