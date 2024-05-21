pragma solidity ^0.8.20;

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";

// todo: move this to an interface
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/// @title GovernanceOFTAdapter
/// @author Aragon
/// @notice locks and unlocks a governance token to allow it to be bridged to another network
/// @dev TODO: this can be made into a proxy contract (clone) to save gas
/// @dev TODO: decide if we want to add DAO_AUTHORIZABLE to the contract
///      to do this we will need to reach into the OFT contract and review
///      if its safe to make it a proxy with the constructor initialization
/// @dev TODO: the delegation wrapper:
///
contract GovernanceOFTAdapter is OFTAdapter {
    /// @param _token the governance token to be locked, should be a governance ERC20
    /// @param _voteProxy the vote proxy contract that will be the delegate of the governance token
    /// @dev   should be the receiving contract on this chain that will relay votes to voting plugins
    /// @dev   if set to address(0) will self delegate which will prevent crosschain votes from being counted
    ///        without modification to the contract
    /// @param _lzEndpoint the endpoint of the LayerZero network on this network
    /// @param _dao the DAO that will be the owner of the adapter
    constructor(
        address _token,
        address _voteProxy,
        address _lzEndpoint,
        /* todo rename to delegate to be consistent */
        address _dao
    ) OFTAdapter(_token, _lzEndpoint, _dao) {
        // self delegate if no vote proxy is set
        // warning: this contract has no way of voting, so this prevents crosschain votes being counted
        // until the vote proxy is set
        address delegateAddress = _voteProxy == address(0) ? address(this) : _voteProxy;
        _delegate(delegateAddress);
    }

    // todo: replace with OSx permissions
    modifier auth(bytes32 _role) {
        _;
    }

    // /// @notice overrides the default behavior of 6 decimals as we only use EVM chains
    // /// @dev check carefully the implications of this
    // function sharedDecimals() public pure override returns (uint8) {
    //     return 18;
    // }

    /// here we can allow delegation to a vote proxy contract
    function delegate(address _to) public auth(keccak256("SET_CROSSCHAIN_DELEGATE_ID")) {
        _delegate(_to);
    }

    function _delegate(address _to) internal {
        ERC20Votes(address(innerToken)).delegate(_to);
    }

    // todo: should we add a sweep function here:
    // wrong tokens sent to the adapter?
    // tokens transferred but not locked via the send mechanism?
}
