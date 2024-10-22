// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {OFTAdapterUpgradeable} from "@oapp-upgradeable/aragon-oft/OFTAdapterUpgradeable.sol";

/// @title GovernanceOFTAdapter
/// @author Aragon
/// @notice Locks and unlocks a governance token to allow it to be bridged to another network
/// @dev This contract must be a singleton for the entire crosschain system and deployed
/// On the execution chain. It can delegate votes to other contracts to allow bridged tokens
/// to still be used for voting via cross chain messages.
contract GovernanceOFTAdapter is OFTAdapterUpgradeable, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    /// @param _token The governance token to be locked, should allow for delegation.
    /// @param _voteProxy The vote proxy contract on this network
    /// that will receive the voting power of the locked tokens.
    /// @param _lzEndpoint The endpoint of the LayerZero network on this network.
    /// @param _dao The DAO that will be the owner of this contract.
    function initialize(
        address _token,
        address _voteProxy,
        address _lzEndpoint,
        address _dao
    ) external initializer {
        __OFTAdapter_init(_token, _lzEndpoint, _dao);
        _delegate(_voteProxy);
    }

    /// @notice Delegates the voting power of the locked tokens to another address.
    /// @param _to The address to delegate the voting power to.
    function delegate(address _to) public auth(OAPP_ADMINISTRATOR_ID) {
        _delegate(_to);
    }

    /// @dev Internal function to allow bypassing the auth modifier.
    function _delegate(address _to) internal {
        IVotes(address(innerToken)).delegate(_to);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~
    /// ------- Upgrades ------
    /// ~~~~~~~~~~~~~~~~~~~~~~~

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(OAPP_ADMINISTRATOR_ID) {}

    uint256[50] private __gap;
}
