// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IOAppCore} from "@lz-oapp/interfaces/IOAppCore.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {Packet} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ISendLib.sol";
import {GUID} from "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/GUID.sol";
import {OFTMsgCodec} from "@lz-oft/libs/OFTMsgCodec.sol";

// aragon contracts
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";

// internal contracts
import {GovernanceERC20} from "@execution-chain/token/GovernanceERC20.sol";
import {GovernanceERC20VotingChain as GovernanceERC20Burnable} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

// internal test utils
import "utils/converters.sol";
import {MockDAOSimplePermission as MockDAO} from "test/mocks/MockDAO.sol";
import {MockOAppReceiver} from "test/mocks/MockOAppReceiver.sol";

/**
 * This test covers a destination chain receipt of an OFT transfer
 */
contract TestOFTTokenBridge is TestHelper {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using OFTMsgCodec for bytes;

    address dao;
    GovernanceERC20Burnable token;

    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint32 constant EID_VOTING_CHAIN = 2;

    function setUp() public override {
        // no need to super the testHelper as it does nothing in its own setup

        // deploy the DAO
        dao = address(new MockDAO());
    }

    /// we test the use of the sending packets on a single chain
    function test_canSendAPacketOnVotingChain() public {
        _setupToken();

        // 1. setup 2 endpoints
        // code for simple message lib is much simpler
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        address endpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
        address endpointVotingChain = endpoints[EID_VOTING_CHAIN];

        // 2. deploy the OFTAdapter connected to the first endpoint
        GovernanceOFTAdapter sendContract = new GovernanceOFTAdapter({
            _token: address(token),
            _voteProxy: address(0),
            _lzEndpoint: endpointExecutionChain,
            _dao: dao
        });

        // 3. deploy the mock reciever oapp connected to the second endpoint
        MockOAppReceiver receiptContract = new MockOAppReceiver(endpointVotingChain, dao);

        // 4. wire both contracts to each other
        uint32 eidAdapter = ((sendContract).endpoint()).eid();
        uint32 eidReceiver = ((receiptContract).endpoint()).eid();

        // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
        sendContract.setPeer(eidReceiver, addressToBytes32(address(receiptContract)));
        receiptContract.setPeer(eidAdapter, addressToBytes32(address(sendContract)));

        // enhance tracing
        vm.label(address(receiptContract), "RECEIVER");
        vm.label(address(sendContract), "ADAPTER");

        // encode with empty message
        bytes memory encodedPacket = _makePacket(
            bytes(""),
            address(sendContract),
            address(receiptContract)
        );

        // this needs sufficient gas or you will OOG
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50_000, 0);

        this.schedulePacket(encodedPacket, options);

        assertEq(
            receiptContract.received(),
            false,
            "receiver should not have received the message"
        );

        _bridgeMessage(EID_VOTING_CHAIN, address(receiptContract));

        assertEq(receiptContract.received(), true, "receiver should have received the message");
    }

    /// we simulate the destination side: minting of tokens
    /// @dev this is a cool test BUT it's quite fiddly and a lot of work on the layerZero internals
    /// when we are closer to finalizing the contracts we can come back to this to fully understand
    /// the packet logic
    // function test_canSendToOFTBridgeAndMint() public {
    //     address tokenReceiver = address(420);
    //     // Layer zero encodes with a max size of type(uint64).max
    //     // TODO: check how this works cross chain...we may need to adjust scales here
    //     uint64 amount = 1000;

    //     _setupToken();

    //     // 1. setup 2 endpoints
    //     // code for simple message lib is much simpler
    //     setUpEndpoints(2, LibraryType.SimpleMessageLib);

    //     address endpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
    //     address endpointVotingChain = endpoints[EID_VOTING_CHAIN];

    //     // 2. deploy the OFTAdapter connected to the first endpoint
    //     GovernanceOFTAdapter sendContract = new GovernanceOFTAdapter({
    //         _token: address(token),
    //         _voteProxy: address(0),
    //         _lzEndpoint: endpointExecutionChain,
    //         _dao: dao
    //     });

    //     // 3. deploy the mock reciever oapp connected to the second endpoint
    //     OFTTokenBridge receiptContract = new OFTTokenBridge(
    //         address(token),
    //         endpointVotingChain,
    //         dao
    //     );

    //     // 4. wire both contracts to each other
    //     uint32 eidSender = ((sendContract).endpoint()).eid();
    //     uint32 eidReceiver = ((receiptContract).endpoint()).eid();

    //     // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
    //     sendContract.setPeer(eidReceiver, addressToBytes32(address(receiptContract)));
    //     receiptContract.setPeer(eidSender, addressToBytes32(address(sendContract)));

    //     // enhance tracing
    //     vm.label(address(receiptContract), "RECEIVER");
    //     vm.label(address(sendContract), "ADAPTER");

    //     bytes memory encodedPacket = _makePacket(
    //         // this is the OFT codec for the packed message with no further composition
    //         abi.encodePacked(addressToBytes32(tokenReceiver), amount),
    //         address(sendContract),
    //         address(receiptContract)
    //     );

    //     // this needs sufficient gas or you will OOG
    //     // TODO: GAS
    //     bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

    //     this.schedulePacket(encodedPacket, options);

    //     verifyPackets(EID_VOTING_CHAIN, address(receiptContract));

    //     // the token balance on the destination should be the mint quantity
    //     assertEq(
    //         token.balanceOf(tokenReceiver),
    //         1000,
    //         "receiver should have received the minted tokens"
    //     );

    //     // now send it back and the tokens should be burned
    //     vm.deal(tokenReceiver, 1000 ether);
    //     vm.startPrank(tokenReceiver);
    //     {
    //         // TODO: GAS
    //         bytes memory optionsBack = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
    //             500000,
    //             0
    //         );
    //         SendParam memory sendParams = SendParam({
    //             dstEid: EID_EXECUTION_CHAIN,
    //             to: addressToBytes32(address(sendContract)),
    //             amountLD: amount,
    //             minAmountLD: amount,
    //             extraOptions: optionsBack,
    //             composeMsg: bytes(""),
    //             oftCmd: bytes("")
    //         });

    //         // fetch a quote
    //         MessagingFee memory msgFee = receiptContract.quoteSend(sendParams, false);
    //         assertEq(msgFee.lzTokenFee, 0, "lz fee should be 0");
    //         assertGt(msgFee.nativeFee, 0, "fee should be > 0");

    //         // send the message
    //         token.approve(address(receiptContract), 10 ether);
    //         receiptContract.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));

    //         // check he now has no tokens
    //         assertEq(token.balanceOf(tokenReceiver), 0, "receiver should have no tokens");
    //     }
    //     vm.stopPrank();
    // }

    // utilities

    /// @dev this is a bit more descriptive IMO
    function _bridgeMessage(uint32 _eid, address _oapp) internal {
        verifyPackets(_eid, _oapp);
    }

    function _makePacket(
        bytes memory _message,
        address _sendContract,
        address _receiptContract
    ) internal pure returns (bytes memory encodedPacket) {
        uint64 nonce = 1;
        bytes32 paddedReceiver = addressToBytes32(_receiptContract);
        Packet memory packet = Packet({
            nonce: nonce,
            srcEid: EID_EXECUTION_CHAIN,
            sender: _sendContract,
            dstEid: EID_VOTING_CHAIN,
            receiver: paddedReceiver,
            guid: GUID.generate(
                nonce,
                EID_EXECUTION_CHAIN,
                _sendContract,
                EID_VOTING_CHAIN,
                paddedReceiver
            ),
            message: _message
        });
        return PacketV1Codec.encode(packet);
    }

    // shared setups

    function _setupToken() private {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](1),
            amounts: new uint256[](1)
        });

        mintSettings.receivers[0] = address(this);

        // deploy the governanceERC20 token
        token = new GovernanceERC20Burnable(IDAO(dao), "MockToken", "MCK");
    }
}
