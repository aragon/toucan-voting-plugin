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

    /// @notice Thrown when a call in the execute function reverts.
    error ExecuteFailed();

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
    /// @param actions The array of actions to execute.
    function execute(IDAO.Action[] memory actions) external auth(OAPP_ADMINISTRATOR_ID) {
        for (uint i = 0; i < actions.length; i++) {
            (bool success, ) = address(actions[i].to).call{value: actions[i].value}(
                actions[i].data
            );
            if (!success) revert ExecuteFailed();
        }
    }

    /// @dev Gap for storage slots in upgrades.
    uint256[50] private __gap;
}
