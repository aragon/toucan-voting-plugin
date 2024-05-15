pragma solidity ^0.8.20;

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

/// @title GovernanceOFTAdapter
/// @author Aragon
/// @notice locks and unlocks a governance token to allow it to be bridged to another network
/// @dev TODO: this can be made into a proxy contract (clone) to save gas
/// @dev TODO: decide if we want to add DAO_AUTHORIZABLE to the contract
///      to do this we will need to reach into the OFT contract and review
///      if its safe to make it a proxy with the constructor initialization
contract GovernanceOFTAdapter is OFTAdapter {
    /// @param _token the governance token to be locked, should be a governance ERC20
    /// @param _lzEndpoint the endpoint of the LayerZero network on this network
    /// @param _dao the DAO that will be the owner of the adapter
    constructor(
        address _token,
        address _lzEndpoint,
        address _dao
    ) OFTAdapter(_token, _lzEndpoint, _dao) {}

    /// @notice overrides the default behavior of 6 decimals as we only use EVM chains
    function sharedDecimals() public pure override returns (uint8) {
        return 18;
    }
}
