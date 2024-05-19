pragma solidity ^0.8.0;

/// Codec because it makes me feel fancy and layer zero chads do it.
library ProposalIdCodec {
    // we have 32 bits of unused space
    function encode(
        address _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp
    ) internal pure returns (uint256 proposalId) {
        uint256 addr = uint256(uint160(_plugin));
        return
            (addr << 96) |
            (uint256(_proposalStartTimestamp) << 64) |
            ((uint256(_proposalEndTimestamp)) << 32);
        // 32 bits of unused space
    }

    function decode(
        uint256 _proposalId
    ) internal pure returns (address plugin, uint32 startTimestamp, uint32 endtimestamp) {
        // shift out the redundant bits then cast to the correct type
        plugin = address(uint160(_proposalId >> 96));
        startTimestamp = uint32(_proposalId >> 64);
        endtimestamp = uint32(_proposalId >> 32);
    }
}
