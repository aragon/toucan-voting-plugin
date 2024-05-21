pragma solidity ^0.8.0;

/// at the moment this is the same as abi.encodePacked but we're thinking through the problem in fixed size chunks
library ProposalIdCodec {
    // we have 32 bits of unused space
    function encode(
        address _plugin,
        uint32 _proposalStartTimestamp,
        uint32 _proposalEndTimestamp
    ) internal pure returns (uint256 proposalId) {
        uint256 addr = uint256(uint160(_plugin));
        return
            (addr << 64) |
            (uint256(_proposalStartTimestamp) << 32) |
            uint256(_proposalEndTimestamp);
    }

    function decode(
        uint256 _proposalId
    ) internal pure returns (address plugin, uint32 startTimestamp, uint32 endtimestamp) {
        // shift out the redundant bits then cast to the correct type
        plugin = address(uint160(_proposalId >> 64));
        startTimestamp = uint32(_proposalId >> 32);
        endtimestamp = uint32(_proposalId);
    }

    function plugin(uint _proposalId) internal pure returns (address) {
        return address(uint160(_proposalId >> 64));
    }

    function startTimestamp(uint _proposalId) internal pure returns (uint32) {
        return uint32(_proposalId >> 32);
    }

    function endTimestamp(uint _proposalId) internal pure returns (uint32) {
        return uint32(_proposalId);
    }
}
// Let's explore a delay
