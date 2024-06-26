// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";

/// simple mock for OFT adapter in the case that you dpn't want to actually
/// send to layer zero, but want to call the send function
contract MockOFTAdapter is GovernanceOFTAdapter {
    // override this to avoid actually sending the message
    function _lzSend(
        uint32, // _dstEid,
        bytes memory, // _message,
        bytes memory, // _options,
        MessagingFee memory _fee,
        address //_refundAddress
    ) internal virtual override returns (MessagingReceipt memory receipt) {
        // @dev Push corresponding fees to the endpoint, any excess is sent back to the _refundAddress from the endpoint.
        _payNative(_fee.nativeFee);
        if (_fee.lzTokenFee > 0) _payLzToken(_fee.lzTokenFee);

        /// here we would otherwise call lz send
        receipt.guid = keccak256("MESSAGE SENT");
    }
}
