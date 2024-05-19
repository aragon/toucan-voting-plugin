pragma solidity ^0.8.0;

/// interface for fetching the app-specific chain Id
/// this took 5 minutes to code but its worth thinking if we need it
interface IChainIdOracle {
    function getMaxSizeInBits() external pure returns (uint8 maxSize);

    function getApplicationChainId(
        uint256 _evmChainId
    ) external view returns (uint256 applicationChainId);
}

contract LayerZeroChainIdOracle is IChainIdOracle {
    mapping(uint256 evmChainId => uint256 layerZeroChainId) private _applicationChainIds;

    constructor() {
        // ethereum mainnet
        _applicationChainIds[1] = 30101;

        // zkSync era
        _applicationChainIds[324] = 30165;

        // base
        _applicationChainIds[58453] = 330184;

        // arbitrum one
        _applicationChainIds[4242161] = 30110;

        // polygon
        _applicationChainIds[137] = 30109;
    }

    function getMaxSizeInBits() external pure returns (uint8 maxSize) {
        return 32;
    }

    function getApplicationChainId(
        uint256 _evmChainId
    ) external view override returns (uint256 applicationChainId) {
        return _applicationChainIds[_evmChainId];
    }
}
