// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";

import {OAppSenderUpgradeable, MessagingFee} from "@oapp-upgradeable/aragon-oapp/OAppSenderUpgradeable.sol";
import {bytes32ToAddress} from "@utils/converters.sol";

import {IActionRelay} from "@execution-chain/crosschain/IActionRelay.sol";

/// @title ActionRelay
/// @author Aragon
/// @notice A LayerZero-compatible OApp that allows for sending arbitrary action data across chains.
contract ActionRelay is IActionRelay, OAppSenderUpgradeable, UUPSUpgradeable {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    /// @notice Mapping of actions queued to be relayed.
    mapping(uint256 => QueuedActionRelayParams) public actionsMap;

    /// @notice Holders of this role are allowed to relay actions to another chain.
    bytes32 public constant XCHAIN_ACTION_RELAYER_ID = keccak256("XCHAIN_ACTION_RELAYER");
    bytes32 public constant XCHAIN_ACTION_EXECUTOR_ID = keccak256("XCHAIN_ACTION_EXECUTOR");

    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the OApp with the LayerZero endpoint and DAO.
    /// @param _lzEndpoint The LayerZero endpoint address on this chain.
    /// @param _dao The DAO address, will be the delegate for this OApp.
    function initialize(address _lzEndpoint, address _dao) external initializer {
        __OAppCore_init({_endpoint: _lzEndpoint, _dao: _dao});
    }

    /// @notice The refund address will receive extra gas on the destination chain.
    /// @param _dstEid The layerZero endpoint ID of the destination chain.
    /// @dev Encoded as a 256bit integer in case we want to change the implementation to a different chain Id.
    /// @return The address that will receive the refund. By default this is the LayerZero peer address.
    ///         which should implement a sweep function to recover the funds.
    function refundAddress(uint256 _dstEid) public view virtual returns (address) {
        return bytes32ToAddress(peers[_dstEid.toUint32()]);
    }

    /// @notice Quote the messaging fee required to relay actions to another chain.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _gasLimit The additional gas needed on the destination chain to process the message, surplus will be refunded.
    function quote(
        uint256 _callId,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        QueuedActionRelayParams memory action = actionsMap[_callId];

        if (!actionsMap[_callId].queued) {
            revert ActionNotQueued();
        }

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption({
            _gas: _gasLimit,
            _value: 0
        });
        MessagingFee memory fee = _quote({
            _dstEid: action.dstEid,
            _message: action.message,
            _options: options,
            _payInLzToken: false
        });
        return LzSendParams({gasLimit: _gasLimit, fee: fee, options: options});
    }

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
    ) public auth(XCHAIN_ACTION_RELAYER_ID) {
        bytes memory message = abi.encode(_callId, _actions, _allowFailureMap);
        _queueRelayActions(_callId, _dstEid, message);
    }

    function _queueRelayActions(uint256 _callId, uint32 _dstEid, bytes memory _message) internal {
        if (actionsMap[_callId].queued) {
            revert ActionAlreadyQueued();
        }

        if (_message.length == 0) {
            revert ActionDoesNotContainMessage();
        }

        actionsMap[_callId] = QueuedActionRelayParams({
            dstEid: _dstEid,
            message: _message,
            refundAddress: refundAddress(_dstEid),
            executed: false,
            queued: true
        });

        emit ActionsQueued(_callId, _dstEid, _message);
    }

    /// @notice Relay actions to another chain. Requires the sender to be authorized and the peer OApp to be set.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _params The LayerZero parameters required to send the message.
    function executeRelayActions(
        uint256 _callId,
        LzSendParams calldata _params
    ) public payable auth(XCHAIN_ACTION_EXECUTOR_ID) returns (MessagingReceipt memory receipt) {
        QueuedActionRelayParams memory action = actionsMap[_callId];
        if (!actionsMap[_callId].queued) {
            revert ActionNotQueued();
        }
        if (action.executed) {
            revert ActionAlreadyExecuted();
        }

        actionsMap[_callId].executed = true;

        receipt = _lzSend({
            _dstEid: action.dstEid,
            _message: action.message,
            _options: _params.options,
            _fee: _params.fee,
            _refundAddress: action.refundAddress
        });

        emit ActionsRelayed(_callId, action.dstEid, receipt);
    }

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(OAPP_ADMINISTRATOR_ID) {}

    uint256[49] private __gap;
}
