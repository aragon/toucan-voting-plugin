// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// SKETCH, DONT ASSUME THIS IS REAL
/// If using LayerZero properly, you would want to do the following:
/// 1. In constructor: endpoint.setDelegate(address(this))
/// 2. TransferOWnership to address(this) in constructor
/// Now the only way to change settings is to use the aragon permissions system and executeSelf
abstract contract AragonOwnable is DaoAuthorizable, Ownable {
    bytes32 constant ARAGON_OWNABLE_ID = keccak256("ARAGON_OWNABLE");

    // map OZ Ownable to Aragon Permission system.
    // the owner must be set to this contract
    // then the auth can be set using aragon permissions systems
    // this is potentially easier than remembering to change all the ownable functions
    function _executeSelf(
        bytes[] calldata data,
        uint[] memory values
    ) internal auth(ARAGON_OWNABLE_ID) {
        require(owner() == address(this), "AragonOwnable: not self-owned");
        for (uint i = 0; i < data.length; i++) {
            (bool success, ) = address(this).call{value: values[i]}(data[i]);
            require(success, "AragonOwnable: execution failed");
        }
    }

    function executeSelf(bytes[] calldata data, uint[] calldata values) external payable {
        _executeSelf(data, values);
    }

    /// @dev nonpayable version of executeSelf, just executes the calldata
    function executeSelf(bytes[] calldata data) external {
        _executeSelf(data, new uint[](data.length));
    }

    /// proxies?
    function _transferOwnership(address newOwner) internal override {
        bool firstTransfer = owner() == address(0);
        if (!firstTransfer) {
            require(newOwner == address(this), "AragonOwnable: force self-ownership");
        }
        super._transferOwnership(newOwner);
    }
}
