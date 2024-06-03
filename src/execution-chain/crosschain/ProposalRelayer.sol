// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {OAppSenderUpgradeable, MessagingFee} from "@oapp-upgradeable/oapp/OAppSenderUpgradeable.sol";
import {OptionsBuilder} from "@lz-oapp/libs/OptionsBuilder.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import "utils/converters.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract ProposalRelayer is OAppSenderUpgradeable, DaoAuthorizableUpgradeable {
    using OptionsBuilder for bytes;
    using SafeCast for uint256;

    // should be set to the DAO or given to an execution plugin
    bytes32 public constant XCHAIN_PROPOSAL_RELAY_ID = keccak256("XCHAIN_PROPOSAL_RELAY");

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

    event ProposalRelayed(uint256 proposalId, uint256 destinationEid);

    function initialize(address _lzEndpoint, address _dao) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __OAppCore_init({_endpoint: _lzEndpoint, _delegate: _dao});
    }

    function _chainId() internal view returns (uint256) {
        return block.chainid;
    }

    // The dao should fetch a quote before creating the proposal
    function quote(
        uint256 _proposalId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        uint32 _dstEid,
        uint128 _gasLimit
    ) external view returns (LzSendParams memory params) {
        bytes memory message = abi.encode(_proposalId, _actions, _allowFailureMap, _chainId());
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

    /// @notice The refund address will receive extra gas on the destination chain.
    /// @param _dstEid The layerZero endpoint ID of the destination chain.
    /// @dev Encoded as a 256bit integer in case we want to change the implementation to a different chain Id.
    /// @return The address that will receive the refund. By default this is the LayerZero peer address.
    ///         which should implement a sweep function to recover the funds.
    function refundAddress(uint256 _dstEid) public view virtual returns (address) {
        return bytes32ToAddress(peers[_dstEid.toUint32()]);
    }

    function relayProposal(
        uint256 proposalId,
        IDAO.Action[] memory actions,
        uint256 allowFailureMap,
        LzSendParams memory params
    ) external payable auth(XCHAIN_PROPOSAL_RELAY_ID) {
        bytes memory message = abi.encode(proposalId, actions, allowFailureMap, _chainId());

        _lzSend({
            _dstEid: params.dstEid,
            _message: message,
            _options: params.options,
            _fee: params.fee,
            _refundAddress: refundAddress(params.dstEid)
        });
    }
}
