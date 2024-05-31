// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {OFTAdapter} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFTAdapter.sol";
import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";

/// @title GovernanceOFTAdapter
/// @author Aragon
/// @notice Locks and unlocks a governance token to allow it to be bridged to another network
/// @dev This contract must be a singleton for the entire crosschain system and deployed
/// On the execution chain. It can delegate votes to other contracts to allow bridged tokens
/// to still be used for voting via cross chain messages.
/// @dev TODO: this can be made into a proxy contract (clone) to save gas
contract GovernanceOFTAdapter is OFTAdapter, DaoAuthorizable {
    /// @notice Grants the ability to change the delegated voting address on this network for all bridged tokens.
    bytes32 public constant SET_CROSSCHAIN_DELEGATE_ID = keccak256("SET_CROSSCHAIN_DELEGATE");

    /// @param _token The governance token to be locked, should allow for delegation.
    /// @param _voteProxy The vote proxy contract on this network
    /// that will receive the voting power of the locked tokens.
    /// @param _lzEndpoint The endpoint of the LayerZero network on this network.
    /// @param _dao The DAO that will be the owner of this contract.
    constructor(
        address _token,
        address _voteProxy,
        address _lzEndpoint,
        address _dao
    ) OFTAdapter(_token, _lzEndpoint, _dao) DaoAuthorizable(IDAO(_dao)) {
        _delegate(_voteProxy);
    }

    // /// @notice overrides the default behavior of 6 decimals as we only use EVM chains
    // /// @dev check carefully the implications of this
    // function sharedDecimals() public pure override returns (uint8) {
    //     return 18;
    // }

    /// @notice Delegates the voting power of the locked tokens to another address.
    /// @param _to The address to delegate the voting power to.
    function delegate(address _to) public auth(SET_CROSSCHAIN_DELEGATE_ID) {
        _delegate(_to);
    }

    /// @dev Internal function to allow bypassing the auth modifier.
    function _delegate(address _to) internal {
        IVotes(address(innerToken)).delegate(_to);
    }
}
