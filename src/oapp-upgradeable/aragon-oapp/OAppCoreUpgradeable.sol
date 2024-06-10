// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IOAppCore, ILayerZeroEndpointV2} from "@lz-oapp/interfaces/IOAppCore.sol";

import {AragonOAppAuthorizable} from "./AragonOAppAuthorizable.sol";

/**
 * @title Aragon OAppCoreUpgradeable
 * @notice A layer zero primitive that uses the Aragon OSx permission management system.
 * @dev Abstract contract implementing the IOAppCore interface with basic OApp configurations.
 */
abstract contract OAppCoreUpgradeable is IOAppCore, AragonOAppAuthorizable {
    // The LayerZero endpoint associated with the given OApp
    /// @dev UPGRADES immutable in the non-upgradeable contract
    ILayerZeroEndpointV2 public endpoint;

    // Mapping to store peers associated with corresponding endpoints
    mapping(uint32 eid => bytes32 peer) public peers;

    /// @notice Thrown if trying to set the delegate as it must always be address(this)
    error SetDelegateProhibited();

    /**
     * @dev UPGRADES constructor in the non-upgradeable contract
     * @dev initialize the OAppCore with the provided endpoint and delegate.
     * @param _endpoint The address of the LOCAL Layer Zero endpoint.
     * @param _dao The DAO who will own the permission system for this contract.
     *
     */
    function __OAppCore_init(address _endpoint, address _dao) internal onlyInitializing {
        __AragonOAppAuthorizableInit(_dao);
        __OAppCore_init_unchained(_endpoint);
    }

    /// @notice Sets the delegate for layer zero to be the address of this contract.
    /// This prevents changes to the contract outside of the Aragon permissions system.
    /// @dev The AragonOappAuthorizable provides a 'selfExecute' function which must be used to make changes.
    /// This is guarded by an Auth modifier so can be granted to addresses by the DAO in the usual way.
    function __OAppCore_init_unchained(address _endpoint) internal onlyInitializing {
        endpoint = ILayerZeroEndpointV2(_endpoint);
        endpoint.setDelegate(address(this));
    }

    /**
     * @notice Sets the peer address (OApp instance) for a corresponding endpoint.
     * @param _eid The endpoint ID.
     * @param _peer The address of the peer to be associated with the corresponding endpoint.
     *
     * @dev Only the owner/admin of the OApp can call this function.
     * @dev Indicates that the peer is trusted to send LayerZero messages to this OApp.
     * @dev Set this to bytes32(0) to remove the peer address.
     * @dev Peer is a bytes32 to accommodate non-evm chains.
     */
    function setPeer(uint32 _eid, bytes32 _peer) public virtual auth(OAPP_ADMINISTRATOR_ID) {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @notice Internal function to get the peer address associated with a specific endpoint; reverts if NOT set.
     * ie. the peer is set to bytes32(0).
     * @param _eid The endpoint ID.
     * @return peer The address of the peer associated with the specified endpoint.
     */
    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) revert NoPeer(_eid);
        return peer;
    }

    /// @notice We prohibit changing the delegate as this would allow admins to bypass the permission model of the OApp.
    function setDelegate(address) public view auth(OAPP_ADMINISTRATOR_ID) {
        revert SetDelegateProhibited();
    }

    /// @dev UPGRADES added for future storage vars
    uint256[48] private __gap;
}
