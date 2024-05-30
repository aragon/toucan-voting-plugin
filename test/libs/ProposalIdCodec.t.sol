// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import {ProposalIdCodec, ProposalId} from "@libs/ProposalIdCodec.sol";

contract ProposalIdCodecTest is Test {
    using ProposalIdCodec for uint256;

    function testEncode(
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalId = ProposalIdCodec.encode(
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        assertEq(proposalId.getPlugin(), plugin);
        assertEq(proposalId.getStartTimestamp(), startTimestamp);
        assertEq(proposalId.getEndTimestamp(), endTimestamp);
        assertEq(proposalId.getBlockSnapshotTimestamp(), blockSnapshotTimestamp);
    }

    function testDecode(
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalId = ProposalIdCodec.encode(
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        (
            address decodedPlugin,
            uint32 decodedStartTimestamp,
            uint32 decodedEndTimestamp,
            uint32 decodedBlockSnapshotTimestamp
        ) = ProposalIdCodec.decode(proposalId);

        assertEq(decodedPlugin, plugin);
        assertEq(decodedStartTimestamp, startTimestamp);
        assertEq(decodedEndTimestamp, endTimestamp);
        assertEq(decodedBlockSnapshotTimestamp, blockSnapshotTimestamp);
    }

    function testToStruct(
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp
    ) public pure {
        uint256 proposalId = ProposalIdCodec.encode(
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        ProposalId memory proposalStruct = proposalId.toStruct();

        assertEq(proposalStruct.plugin, plugin);
        assertEq(proposalStruct.startTimestamp, startTimestamp);
        assertEq(proposalStruct.endTimestamp, endTimestamp);
        assertEq(proposalStruct.blockSnapshotTimestamp, blockSnapshotTimestamp);
    }

    function testIsOpen(
        address plugin,
        uint32 startTimestamp,
        uint32 endTimestamp,
        uint32 blockSnapshotTimestamp,
        uint32 warpTo
    ) public pure {
        uint256 proposalId = ProposalIdCodec.encode(
            plugin,
            startTimestamp,
            endTimestamp,
            blockSnapshotTimestamp
        );

        vm.assume(startTimestamp > 0);
        vm.assume(endTimestamp < type(uint32).max);

        assert(!proposalId.isOpen(warpTo));

        warpTo = startTimestamp - 1;
        assert(!proposalId.isOpen(warpTo));

        warpTo = startTimestamp;
        assert(proposalId.isOpen(warpTo));

        warpTo = endTimestamp;
        assert(proposalId.isOpen(warpTo));

        warpTo = endTimestamp + 1;
        assert(!proposalId.isOpen(warpTo));
    }
}