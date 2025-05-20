// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";

import {OAppSenderUpgradeable, MessagingFee} from "@oapp-upgradeable/aragon-oapp/OAppSenderUpgradeable.sol";
import {bytes32ToAddress} from "@utils/converters.sol";

/// @title ActionRelay
/// @author Aragon
/// @notice A LayerZero-compatible OApp that allows for sending arbitrary action data across chains.
interface IActionRelay {
    /// @notice Actions ready to be relayed to another chain.
    /// @param dstEid The LayerZero endpoint ID of the execution chain.
    /// @param message The encoded message to be sent to the destination chain.
    /// @param refundAddress The address that will receive the refund if the transaction fails.
    struct QueuedActionRelayParams {
        uint32 dstEid;
        bytes message;
        address refundAddress;
        bool executed;
        bool queued;
    }

    /// @notice Additional Layer Zero params required to send a cross chain message.
    /// @param dstEid The LayerZero endpoint ID of the execution chain.
    /// @param gasLimit The additional gas needed on the execution chain to process the message, surplus will be refunded.
    /// @param fee The messaging fee required to send the message, this is sent to LayerZero.
    /// @param options Additional options required to send the message, these are encoded as bytes.
    struct LzSendParams {
        uint128 gasLimit;
        MessagingFee fee;
        bytes options;
    }

    /// @notice Emitted when actions have been successfully relayed to another chain.
    /// @param callId A unique identifier for the relayed actions, such as a proposal ID.
    /// @param destinationEid The LayerZero endpoint ID of the destination chain.
    event ActionsRelayed(
        uint256 indexed callId,
        uint256 indexed destinationEid,
        MessagingReceipt receipt
    );

    /// @notice Emitted when actions are queued for relaying to another chain.
    /// @param callId A unique identifier for the relayed actions, such as a proposal ID.
    /// @param destinationEid The LayerZero endpoint ID of the destination chain.
    /// @param message The encoded message to be sent to the destination chain.
    event ActionsQueued(uint256 indexed callId, uint256 indexed destinationEid, bytes message);

    error ActionNotQueued();
    error ActionAlreadyQueued();
    error ActionAlreadyExecuted();
    error ActionDoesNotContainMessage();

    /// @notice The refund address will receive extra gas on the destination chain.
    /// @param _dstEid The layerZero endpoint ID of the destination chain.
    /// @dev Encoded as a 256bit integer in case we want to change the implementation to a different chain Id.
    /// @return The address that will receive the refund. By default this is the LayerZero peer address.
    ///         which should implement a sweep function to recover the funds.
    function refundAddress(uint256 _dstEid) external view returns (address);

    /// @notice Quote the messaging fee required to relay actions to another chain.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _gasLimit The additional gas needed on the destination chain to process the message, surplus will be refunded.
    function quote(
        uint256 _callId,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params);

    /// @notice Relay actions to another chain. Requires the sender to be authorized and the peer OApp to be set.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _actions The actions to relay to the destination chain, including value, target and calldata.
    /// @param _allowFailureMap A bitmap of actions that are allowed to fail.
    /// @param _dstEid The LayerZero endpoint ID of the destination chain.
    function queueRelayActions(
        uint256 _callId,
        uint32 _dstEid,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap
    ) external;

    /// @notice Relay actions to another chain. Requires the sender to be authorized and the peer OApp to be set.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _params The LayerZero parameters required to send the message.
    function executeRelayActions(
        uint256 _callId,
        LzSendParams calldata _params
    ) external payable returns (MessagingReceipt memory receipt);
}
