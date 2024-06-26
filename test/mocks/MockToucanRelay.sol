// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {MessagingParams, MessagingFee, MessagingReceipt} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

contract MockToucanRelay is ToucanRelay {
    constructor() {}

    uint private chainId_;

    struct Voter {
        address voter;
        Tally vote;
    }

    function setProposalState(
        uint256 _proposalId,
        Tally memory _tally,
        Voter[] memory _votes
    ) public {
        proposals[_proposalId].tally = _tally;
        for (uint256 i = 0; i < _votes.length; i++) {
            address voter = _votes[i].voter;
            Tally memory vote = _votes[i].vote;
            proposals[_proposalId].voters[voter] = vote;
        }
    }

    function setProposalState(uint256 _proposalId, Tally memory _tally) public {
        proposals[_proposalId].tally = _tally;
    }

    function setChainId(uint id) public {
        chainId_ = id;
    }

    function _chainId() internal view override returns (uint) {
        if (chainId_ == 0) {
            return block.chainid;
        } else {
            return chainId_;
        }
    }

    function chainId() external view returns (uint) {
        return _chainId();
    }

    function _lzReceive(bytes calldata message, Origin calldata o, bytes calldata d) external pure {
        bytes32 g;
        address e;
        _lzReceive(o, g, message, e, d);
    }
}

// adds mock Lz functions for unit testing without the lzHelper
contract MockToucanRelayLzMock is MockToucanRelay {
    bool private _allowDispatch;

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

    function setAllowDispatch(bool allow) public {
        _allowDispatch = allow;
    }

    function getLzSendReceived() public view returns (LzSendReceived memory) {
        return lzSendReceived;
    }

    function canDispatch(uint) public view override returns (bool success, ErrReason e) {
        return (_allowDispatch, ErrReason.None);
    }
}
