// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct ProposalReference {
    uint32 proposalId;
    uint128 plugin;
    uint32 startTimestamp;
    uint32 endTimestamp;
    uint32 blockSnapshotTimestamp;
}

/// @title ProposalRefEncoder
/// @author Aragon
/// @notice Encodes salient information about a proposal into a single 256-bit value that can be used as a unique identifier.
/// @dev A proposal reference is composed of the following fields:
/// - 0:32 bits for a proposal ID. Assuming an auto-incrementing proposal ID starting from zero, this should be more than enough.
/// - 33:160 bits for the first 128 bits of the plugin address on the execution chain.
///   This is truncated to save space but 128 bits should be more than enough to avoid collisions.
/// - 32 bits for the proposal start timestamp when voting opens (160 - 191)
/// - 32 bits for the proposal end timestamp when voting closes (192 - 223)
/// - 32 bits for the proposal block snapshot timestamp - when the voting power must be determined (224 - 255)
/// Note that voting may start after the block snapshot is taken, so take care that right value
/// is used when determining voting power on the voting chains.
/// Also note that if voting cross chain, there is a bridging delay to consider.
library ProposalRefEncoder {
    /// @notice Encodes a proposal reference from the given parameters.
    /// @param _proposalId The ID of the proposal. Must be less than 2^32.
    /// @param _plugin The address of the plugin that created the proposal.
    /// @param _proposalStartTimestamp The timestamp when the proposal voting starts.
    /// @param _proposalEndTimestamp The timestamp when the proposal voting ends.
    /// @param _proposalBlockSnapshotTimestamp The timestamp to check voting power at.
    /// @return proposalRef The encoded proposal data as a uint256.
    function encode(
        uint32 _proposalId,
        address _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp,
        uint32 _proposalBlockSnapshotTimestamp
    ) internal pure returns (uint256 proposalRef) {
        uint128 truncatedAddress = uint128(uint160(_plugin));
        return
            _encode(
                _proposalId,
                truncatedAddress,
                _proposalStartTimestamp,
                _proposalEndTimestamp,
                _proposalBlockSnapshotTimestamp
            );
    }

    /// @notice Encodes a proposal reference from the given parameters.
    /// @dev This function accepts the first 128 bits of the plugin address instead of the full address.
    function _encode(
        uint32 _proposalId,
        uint128 _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp,
        uint32 _proposalBlockSnapshotTimestamp
    ) internal pure returns (uint256 proposalRef) {
        return
            (uint256(_proposalId) << 224) |
            (uint256(_plugin) << 96) |
            (uint256(_proposalStartTimestamp) << 64) |
            (uint256(_proposalEndTimestamp) << 32) |
            uint256(_proposalBlockSnapshotTimestamp);
    }

    /// @notice Decodes a proposal reference into its parameters.
    function decode(
        uint256 _proposalRef
    )
        internal
        pure
        returns (
            uint32 proposalId,
            uint128 plugin,
            uint32 startTimestamp,
            uint32 endtimestamp,
            uint32 blockSnapshotTimestamp
        )
    {
        proposalId = getProposalId(_proposalRef);
        plugin = getTruncatedPlugin(_proposalRef);
        startTimestamp = getStartTimestamp(_proposalRef);
        endtimestamp = getEndTimestamp(_proposalRef);
        blockSnapshotTimestamp = getBlockSnapshotTimestamp(_proposalRef);
    }

    /// @notice Converts a proposal reference into a struct representation.
    function toStruct(uint256 _proposalRef) internal pure returns (ProposalReference memory) {
        (
            uint32 proposalId,
            uint128 plugin,
            uint32 startTimestamp,
            uint32 endTimestamp,
            uint32 blockSnapshotTimestamp
        ) = decode(_proposalRef);
        return
            ProposalReference(
                proposalId,
                plugin,
                startTimestamp,
                endTimestamp,
                blockSnapshotTimestamp
            );
    }

    /// @notice Converts a proposal reference struct into a 256-bit encoded value.
    function fromStruct(ProposalReference memory _proposalRef) internal pure returns (uint256) {
        return
            _encode(
                _proposalRef.proposalId,
                _proposalRef.plugin,
                _proposalRef.startTimestamp,
                _proposalRef.endTimestamp,
                _proposalRef.blockSnapshotTimestamp
            );
    }

    /// @return The proposal ID from a proposal reference.
    function getProposalId(uint256 _proposalRef) internal pure returns (uint32) {
        return uint32(_proposalRef >> 224);
    }

    /// @return The first 128 bits of the plugin address from a proposal reference.
    function getTruncatedPlugin(uint256 _proposalRef) internal pure returns (uint128) {
        return uint128(uint160(_proposalRef >> 96));
    }

    /// @return The start timestamp from a proposal reference.
    function getStartTimestamp(uint256 _proposalRef) internal pure returns (uint32) {
        return uint32(_proposalRef >> 64);
    }

    /// @return The end timestamp from a proposal reference.
    function getEndTimestamp(uint256 _proposalRef) internal pure returns (uint32) {
        return uint32(_proposalRef >> 32);
    }

    /// @return The block snapshot timestamp from a proposal reference.
    function getBlockSnapshotTimestamp(uint256 _proposalRef) internal pure returns (uint32) {
        return uint32(_proposalRef);
    }

    /// @return True if the first 128 bits of the plugin address in the proposal reference match the given address.
    function pluginMatches(uint256 _proposalRef, address _other) internal pure returns (bool) {
        return getTruncatedPlugin(_proposalRef) == uint128(uint160(_other));
    }

    /// @return True if the proposal is open for voting at the given block timestamp.
    /// @dev TODO ERC20 votes requires > _startTs - I think this is different to the block but need to check
    function isOpen(uint256 _proposalRef, uint32 _blockTimestamp) internal pure returns (bool) {
        return
            getStartTimestamp(_proposalRef) < _blockTimestamp &&
            _blockTimestamp < getEndTimestamp(_proposalRef);
    }
}
