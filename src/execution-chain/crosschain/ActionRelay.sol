// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";

import {OAppSenderUpgradeable, MessagingFee} from "@oapp-upgradeable/aragon-oapp/OAppSenderUpgradeable.sol";
import {bytes32ToAddress} from "@utils/converters.sol";

/// @title ActionRelay
/// @author Aragon
/// @notice A LayerZero-compatible OApp that allows for sending arbitrary action data across chains.
contract ActionRelay is OAppSenderUpgradeable, UUPSUpgradeable {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    /// @notice Holders of this role are allowed to relay actions to another chain.
    bytes32 public constant XCHAIN_ACTION_RELAYER_ID = keccak256("XCHAIN_ACTION_RELAYER");

    /// @notice Additional Layer Zero params required to send a cross chain message.
    /// @param dstEid The LayerZero endpoint ID of the execution chain.
    /// @param gasLimit The additional gas needed on the execution chain to process the message, surplus will be refunded.
    /// @param fee The messaging fee required to send the message, this is sent to LayerZero.
    /// @param options Additional options required to send the message, these are encoded as bytes.
    struct LzSendParams {
        uint32 dstEid;
        uint128 gasLimit;
        MessagingFee fee;
        bytes options;
    }

    /// @notice Emitted when actions have been successfully relayed to another chain.
    /// @param callId A unique identifier for the relayed actions, such as a proposal ID.
    /// @param destinationEid The LayerZero endpoint ID of the destination chain.
    event ActionsRelayed(uint256 callId, uint256 destinationEid);

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
    /// @param _actions The actions to relay to the destination chain, including value, target and calldata.
    /// @param _allowFailureMap A bitmap of actions that are allowed to fail.
    /// @param _dstEid The LayerZero endpoint ID of the destination chain.
    /// @param _gasLimit The additional gas needed on the destination chain to process the message, surplus will be refunded.
    function quote(
        uint256 _callId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        uint32 _dstEid,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        bytes memory message = abi.encode(_callId, _actions, _allowFailureMap);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption({
            _gas: _gasLimit,
            _value: 0
        });
        MessagingFee memory fee = _quote({
            _dstEid: _dstEid,
            _message: message,
            _options: options,
            _payInLzToken: false
        });
        return LzSendParams({dstEid: _dstEid, gasLimit: _gasLimit, fee: fee, options: options});
    }

    /// @notice Relay actions to another chain. Requires the sender to be authorized and the peer OApp to be set.
    /// @param _callId The unique identifier for the relayed actions, such as a proposal ID.
    /// @param _actions The actions to relay to the destination chain, including value, target and calldata.
    /// @param _allowFailureMap A bitmap of actions that are allowed to fail.
    /// @param _params Additional Layer Zero params required to send a cross chain message, use the `quote` function to get these.
    function relayActions(
        uint256 _callId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        LzSendParams memory _params
    ) external payable auth(XCHAIN_ACTION_RELAYER_ID) {
        bytes memory message = abi.encode(_callId, _actions, _allowFailureMap);

        _lzSend({
            _dstEid: _params.dstEid,
            _message: message,
            _options: _params.options,
            _fee: _params.fee,
            _refundAddress: refundAddress(_params.dstEid)
        });

        emit ActionsRelayed(_callId, _params.dstEid);
    }

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(OAPP_ADMINISTRATOR_ID) {}
}
