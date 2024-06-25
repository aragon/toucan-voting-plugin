// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IOAppCore} from "@lz-oapp/interfaces/IOAppCore.sol";

import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

/// @title OAappInitializer
/// @notice Allows granting a one-off permission to an address to set OApp settings that cannot be known at deploy time.
/// Specifically, the remote peer of the OApp which has not yet been deployed. Once set, the method cannot be called again, so the permission is useless.
/// The aim here is that the DAO can grant an address the ability to finish cross chain configuration by setting the peer, but then the
/// only way to make further changes is via the DAO itself.
/// @dev This contract should be granted the OAPP_ADMINISTRATOR permission in the DAO and be deployed as a minimal, non-upgradeable proxy.
abstract contract OAppInitializer is DaoAuthorizableUpgradeable {
    /// @notice This permission grants administrative rights to the holder to change OApp settings
    bytes32 public constant INITIALIZER_ID = keccak256("INITIALIZER");

    /// @notice Emitted when a peer is set for a specific endpoint. Prevents further use of this contract.
    bool public initialized;

    /// @notice The OApp that needs to be initialized.
    IOAppCore public oapp;

    /// @notice Emitted when the contract is already initialized, preventing further use.
    error AlreadyInitialized();

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract by instantiating the Aragon permissions and setting the OApp instance.
    /// @param _dao The DAO that will control permissions.
    /// @param _oapp The OApp instance that needs to be initialized.
    function __OAppInitializerUnchained(address _dao, address _oapp) internal onlyInitializing {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __OAppInitializerUnchained(_oapp);
    }

    /// @notice Initializes the contract by setting the OApp instance.
    function __OAppInitializerUnchained(address _oapp) internal onlyInitializing {
        oapp = IOAppCore(_oapp);
    }

    /// @notice Sets the peer address (OApp instance) for a corresponding endpoint.
    /// @param _eid The layer zero endpoint ID on the foreign chain.
    /// @param _peer The address of the peer to be associated with the corresponding endpoint, encoded as bytes32.
    /// @dev This function can only be called once, and only by the holder of INITIALIZER_ID, after that the contract is useless.
    function setPeer(uint32 _eid, bytes32 _peer) public virtual auth(INITIALIZER_ID) {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        IOAppCore(oapp).setPeer(_eid, _peer);
    }

    /// @dev Gap for storage slots in upgrades.
    uint256[48] private __gap;
}
