// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ProposalRefEncoder, ProposalReference} from "@libs/ProposalRefEncoder.sol";
import "@utils/converters.sol";

contract ProposalRefEncoderTest is Test {
    using ProposalRefEncoder for uint256;

    function testEncode(
        uint32 proposalId,
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalRef = ProposalRefEncoder.encode(
            proposalId,
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        assertEq(proposalRef.getProposalId(), proposalId);
        assertEq(proposalRef.pluginMatches(plugin), true);
        assertEq(proposalRef.getStartTimestamp(), startTimestamp);
        assertEq(proposalRef.getEndTimestamp(), endTimestamp);
        assertEq(proposalRef.getBlockSnapshotTimestamp(), blockSnapshotTimestamp);
    }

    function testDecode(
        uint32 proposalId,
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalRef = ProposalRefEncoder.encode(
            proposalId,
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        (
            uint32 decodedProposalId,
            uint128 decodedPlugin,
            uint32 decodedStartTimestamp,
            uint32 decodedEndTimestamp,
            uint32 decodedBlockSnapshotTimestamp
        ) = ProposalRefEncoder.decode(proposalRef);

        assertEq(decodedProposalId, proposalId);
        assertEq(decodedPlugin, addressToUint128(plugin));
        assertEq(decodedStartTimestamp, startTimestamp);
        assertEq(decodedEndTimestamp, endTimestamp);
        assertEq(decodedBlockSnapshotTimestamp, blockSnapshotTimestamp);
    }

    function testToStruct(
        uint32 proposalId,
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalRef = ProposalRefEncoder.encode(
            proposalId,
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        ProposalReference memory proposalStruct = proposalRef.toStruct();

        assertEq(proposalStruct.proposalId, proposalId);
        assertEq(proposalStruct.plugin, addressToUint128(plugin));
        assertEq(proposalStruct.startTimestamp, startTimestamp);
        assertEq(proposalStruct.endTimestamp, endTimestamp);
        assertEq(proposalStruct.blockSnapshotTimestamp, blockSnapshotTimestamp);
    }

    function testIsOpen(
        uint32 proposalId,
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp,
        uint32 blockTs
    ) public pure {
        uint256 proposalRef = ProposalRefEncoder.encode(
            proposalId,
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        vm.assume(startTimestamp > 0);
        vm.assume(endTimestamp < type(uint32).max);

        assert(!proposalRef.isOpen(0));

        blockTs = startTimestamp - 1;
        assert(!proposalRef.isOpen(blockTs));

        blockTs = startTimestamp;
        assert(!proposalRef.isOpen(blockTs));

        if (endTimestamp > startTimestamp) {
            if (endTimestamp - startTimestamp > 1) {
                blockTs = startTimestamp + 1;
                assert(proposalRef.isOpen(blockTs));

                blockTs = endTimestamp - 1;
                assert(proposalRef.isOpen(blockTs));
            }
        }

        blockTs = endTimestamp;
        assert(!proposalRef.isOpen(blockTs));

        blockTs = endTimestamp + 1;
        assert(!proposalRef.isOpen(blockTs));
    }
}
