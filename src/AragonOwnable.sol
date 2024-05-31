pragma solidity ^0.8.0;

import {DaoAuthorizable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// SKETCH, DONT ASSUME THIS IS REAL
abstract contract AragonOwnable is DaoAuthorizable, Ownable {
    bytes32 constant ARAGON_OWNABLE_ID = keccak256("ARAGON_OWNABLE");

    // map OZ Ownable to Aragon Permission system.
    // the owner must be set to this contract
    // then the auth can be set using aragon permissions systems
    // this is potentially easier than remembering to change all the ownable functions
    function executeSelf(bytes calldata data) external payable auth(ARAGON_OWNABLE_ID) {
        require(owner() == address(this), "AragonOwnable: not self-owned");
        (bool success, ) = address(this).call(data);
        require(success, "AragonOwnable: execution failed");
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
