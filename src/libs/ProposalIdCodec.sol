// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/console2.sol";

struct ProposalId {
    address plugin;
    uint32 startTimestamp;
    uint32 endTimestamp;
    uint32 blockSnapshotTimestamp;
}

/// @title ProposalIdCodec
/// @author Aragon
/// @notice ProposalIdCodec is a library for encoding and decoding proposal IDs.
/// @dev Proposal IDs are 256-bit values that encode a plugin address and three timestamps.
/// They should be unique for each proposal on each chain. There may be clashes across chains
/// due to the presence of CREATE2-style deployments, so care should be taken to store them by chain ID.
/// @dev A proposal ID is composed of the following fields:
/// - 160 bits for the plugin address on the execution chain (0 - 159)
/// - 32 bits for the proposal start timestamp when voting opens (160 - 191)
/// - 32 bits for the proposal end timestamp when voting closes (192 - 223)
/// - 32 bits for the proposal block snapshot timestamp - when the voting power must be determined (224 - 255)
/// Note that voting may start after the block snapshot is taken, so take care that right value
/// is used when determining voting power on the voting chains.
library ProposalIdCodec {
    /// @notice Encodes a proposal ID from the given parameters.
    /// @param _plugin The address of the plugin that created the proposal.
    /// @param _proposalStartTimestamp The timestamp when the proposal voting starts.
    /// @param _proposalEndTimestamp The timestamp when the proposal voting ends.
    /// @param _proposalBlockSnapshotTimestamp The timestamp to check voting power at.
    /// @return proposalId The encoded proposal ID.
    function encode(
        address _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp,
        uint32 _proposalBlockSnapshotTimestamp
    ) internal pure returns (uint256 proposalId) {
        uint256 addr = uint256(uint160(_plugin));
        return
            (addr << 96) |
            (uint256(_proposalStartTimestamp) << 64) |
            (uint256(_proposalEndTimestamp) << 32) |
            uint256(_proposalBlockSnapshotTimestamp);
    }

    /// @notice Decodes a proposal ID into its parameters.
    function decode(
        uint256 _proposalId
    )
        internal
        pure
        returns (
            address plugin,
            uint32 startTimestamp,
            uint32 endtimestamp,
            uint32 blockSnapshotTimestamp
        )
    {
        plugin = getPlugin(_proposalId);
        startTimestamp = getStartTimestamp(_proposalId);
        endtimestamp = getEndTimestamp(_proposalId);
        blockSnapshotTimestamp = getBlockSnapshotTimestamp(_proposalId);
    }

    /// @notice Converts a proposal ID into a struct.
    function toStruct(uint256 _proposalId) internal pure returns (ProposalId memory proposalId) {
        (
            address plugin,
            uint32 startTimestamp,
            uint32 endTimestamp,
            uint32 blockSnapshotTimestamp
        ) = decode(_proposalId);
        return ProposalId(plugin, startTimestamp, endTimestamp, blockSnapshotTimestamp);
    }

    function fromStruct(ProposalId memory pid) internal pure returns (uint256) {
        return encode(pid.plugin, pid.startTimestamp, pid.endTimestamp, pid.blockSnapshotTimestamp);
    }

    /// @return The plugin address from a proposal ID.
    function getPlugin(uint256 _proposalId) internal pure returns (address) {
        return address(uint160(_proposalId >> 96));
    }

    /// @return The start timestamp from a proposal ID.
    function getStartTimestamp(uint256 _proposalId) internal pure returns (uint32) {
        return uint32(_proposalId >> 64);
    }

    /// @return The end timestamp from a proposal ID.
    function getEndTimestamp(uint256 _proposalId) internal pure returns (uint32) {
        return uint32(_proposalId >> 32);
    }

    /// @return The block snapshot timestamp from a proposal ID.
    function getBlockSnapshotTimestamp(uint256 _proposalId) internal pure returns (uint32) {
        return uint32(_proposalId);
    }

    /// @return True if the proposal is open for voting at the given block timestamp.
    /// @dev TODO ERC20 votes requires > _startTs - I think this is different to the block but need to check
    function isOpen(uint256 _proposalId, uint32 _blockTimestamp) internal pure returns (bool) {
        return
            getStartTimestamp(_proposalId) < _blockTimestamp &&
            _blockTimestamp < getEndTimestamp(_proposalId);
    }
}
