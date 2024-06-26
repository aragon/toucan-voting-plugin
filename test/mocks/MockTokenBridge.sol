// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

contract MockTokenBridge is OFTTokenBridge {
    function debit(
        uint _amountLD,
        uint _minAmountLD,
        uint32 _dstEid
    ) public returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        return _debit(_amountLD, _minAmountLD, _dstEid);
    }

    function credit(
        address _to,
        uint256 _amountLD,
        uint32 _srcEid
    ) public returns (uint256 amountReceivedLD) {
        return _credit(_to, _amountLD, _srcEid);
    }
}
