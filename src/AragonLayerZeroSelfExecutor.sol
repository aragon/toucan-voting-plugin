// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {OAppCoreUpgradeable} from "@oapp-upgradeable/oapp/OAppCoreUpgradeable.sol";

/// SKETCH, DONT ASSUME THIS IS REAL
/// If using LayerZero properly, you would want to do the following:
/// 1. In constructor: endpoint.setDelegate(address(this))
/// 2. TransferOWnership to address(this) in constructor
/// Now the only way to change settings is to use the aragon permissions system and executeSelf
abstract contract AragonLayerZeroSelfExecutor is DaoAuthorizableUpgradeable, OAppCoreUpgradeable {
    bytes32 constant ARAGON_OWNABLE_ID = keccak256("ARAGON_OWNABLE");

    function __AragonLayerZeroSelfExecutor_init(address _endpoint) internal initializer {
        __AragonLayerZeroSelfExecutor_init_unchained(_endpoint);

        // this is if we keep Lzero ownable, but we could equally remove OWnableUpgradeable and
        // make the layerzero plugin DAOAuthorizableUpgradeable
        _transferOwnership(address(this));
    }

    /// @notice Setting this contract as its own endpoint delegate means that the only was to update
    /// Settings is via executeSelf, which can be controlled by the aragon permissions system.
    function __AragonLayerZeroSelfExecutor_init_unchained(address _endpoint) internal initializer {
        ILayerZeroEndpointV2(_endpoint).setDelegate(address(this));
    }

    // map OZ Ownable to Aragon Permission system.
    // the owner must be set to this contract
    // then the auth can be set using aragon permissions systems
    // this is potentially easier than remembering to change all the ownable functions
    function _executeSelf(
        bytes[] calldata data,
        uint[] memory values
    ) internal auth(ARAGON_OWNABLE_ID) {
        if (data.length != values.length) {
            revert("AragonOwnable: data and values length mismatch");
        }
        for (uint i = 0; i < data.length; i++) {
            // note that we don't set the target to this contract, so we can't call internal functions
            // nor can we call other contracts.
            (bool success, ) = address(this).call{value: values[i]}(data[i]);
            require(success, "AragonOwnable: execution failed");
        }
    }

    /// @notice Executes an array of externally facing function on this contract.
    function executeSelf(bytes[] calldata data, uint[] calldata values) external payable {
        _executeSelf(data, values);
    }

    /// @notice Executes an array of nonpayable externally facing function on this contract.
    function executeSelf(bytes[] calldata data) external {
        _executeSelf(data, new uint[](data.length));
    }
}
