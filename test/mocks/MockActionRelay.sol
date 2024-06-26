// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {ActionRelay} from "@execution-chain/crosschain/ActionRelay.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockActionRelay is ActionRelay {
    struct LzSendReceived {
        uint32 dstEid;
        bytes message;
        address refundAddress;
        MessagingFee fee;
        bytes options;
    }

    LzSendReceived public lzSendReceived;

    function _quote(
        uint32 /* _dstEid */,
        bytes memory /*_message */,
        bytes memory /* _options */,
        bool _payInLzToken
    ) internal pure override returns (MessagingFee memory fee) {
        return MessagingFee(100, _payInLzToken ? 99 : 0);
    }

    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress
    ) internal override returns (MessagingReceipt memory receipt) {
        // @dev Push corresponding fees to the endpoint, any excess is sent back to the _refundAddress from the endpoint.
        _payNative(_fee.nativeFee);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        _getPeerOrRevert(_dstEid);

        lzSendReceived = LzSendReceived({
            dstEid: _dstEid,
            message: _message,
            refundAddress: _refundAddress,
            fee: _fee,
            options: _options
        });

        return MessagingReceipt({guid: keccak256("guid"), nonce: 1234, fee: _fee});
    }

    function getLzSendReceived() public view returns (LzSendReceived memory) {
        return lzSendReceived;
    }
}
