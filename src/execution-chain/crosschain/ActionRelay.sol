// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title ActionRelay
/// @author Aragon
/// @notice A contract that allows for sending arbitrary action data across chains using Hashi pull flow.
contract ActionRelay is UUPSUpgradeable, DaoAuthorizableUpgradeable {
    /// @notice Holders of this role are allowed to relay actions to another chain.
    bytes32 public constant XCHAIN_ACTION_RELAYER_ID = keccak256("XCHAIN_ACTION_RELAYER");

    /// @notice Holders of this role are allowed to upgrade the contract
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR_ID");

    /// @notice Variable used to ensure commitment uniqueness
    uint256 private _nonce;

    /// @notice Emitted when actions have been successfully relayed to another chain.
    /// @param callId A unique identifier for the relayed actions, such as a proposal ID.
    /// @param destinationChainId The destination chain ID.
    /// @param commitment The commitment of the message to execute on the destination chain.
    event ActionsRelayed(uint256 indexed callId, uint256 indexed destinationChainId, bytes32 commitment);

    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {}

    /// @notice Relay actions to another chain. Requires the sender to be authorized and the peer OApp to be set.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _actions The actions to relay to the destination chain, including value, target and calldata.
    /// @param _allowFailureMap A bitmap of actions that are allowed to fail.
    /// @param _destinationChainId The destination chain ID.
    function relayActions(
        uint256 _callId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        uint256 _destinationChainId
    ) external payable auth(XCHAIN_ACTION_RELAYER_ID) returns (bytes32 commitment) {
        bytes memory message =
            abi.encode(block.chainid, _destinationChainId, msg.sender, _nonce, _callId, _actions, _allowFailureMap);
        commitment = keccak256(message);
        unchecked {
            ++_nonce;
        }
        emit ActionsRelayed(_callId, _destinationChainId, commitment);
    }

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(OAPP_ADMINISTRATOR_ID) {}

    uint256[50] private __gap;
}
