// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {ILayerZeroEndpointV2} from "@lz-oapp/interfaces/IOAppCore.sol";

import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

/**
 * @title AragonOAppAuthorizable
 * @notice A layer zero primitive that uses the Aragon OSx permission management system.
 * @dev Standardises a shared permission for all OApp administrative activities.
 */
abstract contract AragonOAppAuthorizable is DaoAuthorizableUpgradeable {
    /// @notice This permission grants administrative rights to the holder to change OApp settings
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR");

    /// @notice Thrown if a user tries to pass a different number of values and calldata to self execute.
    error SelfExecuteDataLengthMismatch(uint256 dataLength, uint256 valuesLength);

    /// @notice Thrown when a call in the self execute function reverts.
    error SelfExecuteFailed();

    /**
     * @dev UPGRADES added to prevent reinitialization of the contract
     * @notice Initializes the contract by instantiating the Aragon permissions.
     * @param _dao The DAO that will control permissions.
     */
    function __AragonOAppAuthorizableInit(address _dao) internal onlyInitializing {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __AragonOAppAuthorizableInit_unchained();
    }

    /// @dev Deliberately left blank for convention.
    function __AragonOAppAuthorizableInit_unchained() internal onlyInitializing {}

    /// @notice Executes an external or public contract call from this contract.
    /// @dev As this function is guarded by the Aragon permission system it allows the DAO to control
    /// cases like Layer Zero endpoint delegation which otherwise would require an external body to hold
    /// critical ownerhsip responsibilities on this contract.
    /// @param data Calldata array to be passed to calls to this contract.
    /// @param values Native value to be sent for any payable functions.
    function _executeSelf(
        bytes[] calldata data,
        uint[] memory values
    ) internal auth(OAPP_ADMINISTRATOR_ID) {
        if (data.length != values.length) {
            revert SelfExecuteDataLengthMismatch(data.length, values.length);
        }
        for (uint i = 0; i < data.length; i++) {
            // note that we don't set the target to this contract, so we can't call internal functions
            // nor can we call other contracts.
            (bool success, ) = address(this).call{value: values[i]}(data[i]);
            if (!success) revert SelfExecuteFailed();
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

    /// @dev Gap for storage slots in upgrades.
    uint256[50] private __gap;
}
