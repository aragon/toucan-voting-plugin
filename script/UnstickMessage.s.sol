// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {OFTMsgCodec} from "@lz-oft/libs/OFTMsgCodec.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IToucanRelayMessage} from "@interfaces/IToucanRelayMessage.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import "@utils/converters.sol";

/**
 * @dev Layer zero messages that arrive in the endpoint can get stuck due to gas issues.
 * One can call the `execute` function in layerzero scan but:
 * 1. This is not a good user experience.
 * 2. The scan doesn't work on testnets
 *
 * For this reason we should know how to resend the message on the destination chain.
 */
contract UnstickDeploy is Script, IVoteContainer {
    ILayerZeroEndpointV2 lzEndpoint =
        ILayerZeroEndpointV2(0x6EDCE65403992e310A62460808c4b910D972f10f);

    /* ---- origin params ---- */
    // Fetch from config
    // uint32 srcEid = 40231; // arb sep
    uint32 srcEid = 40232; // op sep
    // known oapp
    bytes32 sender = addressToBytes32(0x65991B62B5067c1B4941E6F6A97add0e45280a3A);
    // fetch from MessageReceipt or layerZeroScan
    uint64 nonce = 18;

    /*  ----- lzReceive Params ----- */

    // known oapp
    address oapp = 0xA52bEC62C3CA39d999778D671B5024CB7ef7E0a0;

    address tokenRecipient = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;

    // fetch from MessageReceipt or event logs
    bytes32 guid = 0xcf5405159dd380337ac7db214a9c848272bf732062aa46ac14170819e48bf098;

    // logs or known in advance
    uint256 transferQty = 100 ether;

    // oft so no data
    bytes extraData = bytes("");

    // this is a space-saving technique
    uint256 sharedDecimals = 10 ** 12;

    address deployer;

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    // run this as sepolia
    function run() public broadcast {
        // encode the arguments
        Origin memory origin = Origin({srcEid: srcEid, sender: sender, nonce: nonce});

        // // encode the message
        // (bytes memory message, ) = OFTMsgCodec.encode({
        //     _sendTo: addressToBytes32(tokenRecipient),
        //     _amountShared: uint64(transferQty / sharedDecimals),
        //     _composeMsg: extraData
        // });
        bytes memory message = abi.encode(
            IToucanRelayMessage.ToucanVoteMessage({
                votes: Tally({abstain: 0, yes: 1.05e22, no: 3e21}),
                votingChainId: 11155420,
                proposalRef: 154779696380424897416400549484501486953112152826972991694188353312700
            })
        );

        // send the message
        lzEndpoint.lzReceive(origin, oapp, guid, message, extraData);
    }
}
