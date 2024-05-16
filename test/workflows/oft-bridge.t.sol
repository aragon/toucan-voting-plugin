pragma solidity ^0.8.20;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";

// aragon contracts
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";

// internal contracts
import {GovernanceERC20} from "src/token/governance/GovernanceERC20.sol";
import {GovernanceOFTAdapter} from "src/crosschain/GovernanceOFTAdapter.sol";

// internal test utils
import {MockIDAO} from "test/mocks/MockDAO.sol";
import "utils/converters.sol";

/**
 * This test covers the creation of a governance ERC20 token that is then locked inside an OFT container, bridged
 * and the a destination Oapp simply receives it
 */
contract TestXChainOFTBridge is TestHelper {
    using OptionsBuilder for bytes;

    address dao;
    GovernanceERC20 token;

    GovernanceOFTAdapter adapter;
    OAppMockReceiver receiver;

    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint32 constant EID_VOTING_CHAIN = 2;

    function setUp() public override {
        // no need to super the testHelper as it does nothing in its own setup

        // deploy the DAO
        dao = address(new MockIDAO());
    }

    function test_canSetupTheGovernanceERC20() public {
        _setupToken();

        assertEq(token.totalSupply(), 100 ether, "total supply should be 100");
        assertEq(token.balanceOf(address(this)), 100 ether, "balance should be 100");
    }

    function test_canSetupTheOFTAdapter() public {
        _setupToken();
        _initalizeOApps();

        address adapterPeer = bytes32ToAddress(adapter.peers(EID_VOTING_CHAIN));
        address receiverPeer = bytes32ToAddress(receiver.peers(EID_EXECUTION_CHAIN));
        assertEq(adapterPeer, address(receiver), "receiver should be the peer of the adapter");
        assertEq(receiverPeer, address(adapter), "adapter should be the peer of the receiver");

        // check the adapter
        assertEq(address(adapter.token()), address(token), "adapter should have the token address");
    }

    /// test that we can use the governance ERC20 with the adapter
    /// which will then cause the message to be received on the receiver
    function test_canLockAndReceiveMessage() public {
        _setupToken();
        _initalizeOApps();

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(50000, 0);
        SendParam memory sendParams = SendParam({
            dstEid: EID_VOTING_CHAIN,
            to: addressToBytes32(address(receiver)),
            amountLD: 10 ether,
            minAmountLD: 10 ether,
            extraOptions: options,
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        // fetch a quote
        MessagingFee memory msgFee = adapter.quoteSend(sendParams, false);
        assertEq(msgFee.lzTokenFee, 0, "lz fee should be 0");
        assertGt(msgFee.nativeFee, 0, "fee should be > 0");

        // send the message
        token.approve(address(adapter), 10 ether);
        adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));

        // should be in the outbox
        assertEq(receiver.received(), false, "receiver should not yet have received the message");
        assertEq(token.balanceOf(address(adapter)), 10 ether, "adapter should have 10 tokens");

        // send it
        _bridgeMessages(EID_VOTING_CHAIN, address(receiver));

        // should have received the message
        assertEq(receiver.received(), true, "receiver should have received the message");
    }

    // utilities

    /// @dev this is a bit more descriptive IMO
    function _bridgeMessages(uint32 _eid, address _oapp) internal {
        verifyPackets(_eid, _oapp);
    }

    // shared setups

    /// Simple setup by minting 100 tokens to the contract. We use the mock DAO for the auth checks.
    /// Which automatically passes any permission checks.
    function _setupToken() private {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](1),
            amounts: new uint256[](1)
        });

        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 100 ether;

        // deploy the governanceERC20 token
        token = new GovernanceERC20(IDAO(dao), "MockToken", "MCK", mintSettings);
    }

    /// does the base initialization for the layer zero setup
    /// includes setting up the endpoints and the OFTAdapter
    /// at this stage, we try and keep the setup as simple as possible
    /// even though there are dedicated O(n^2) wiring contracts available
    function _initalizeOApps() private {
        // 1. setup 2 endpoints
        // code for simple message lib is much simpler
        setUpEndpoints(2, LibraryType.SimpleMessageLib);

        address endpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
        address endpointVotingChain = endpoints[EID_VOTING_CHAIN];

        // 2. deploy the OFTAdapter connected to the first endpoint
        adapter = new GovernanceOFTAdapter({
            _token: address(token),
            _lzEndpoint: endpointExecutionChain,
            _dao: dao
        });

        // 3. deploy the mock reciever oapp connected to the second endpoint
        receiver = new OAppMockReceiver(endpointVotingChain, dao);

        // 4. wire both contracts to each other
        uint32 eidAdapter = (adapter.endpoint()).eid();
        uint32 eidReceiver = (receiver.endpoint()).eid();

        // format is {localOApp}.setPeer({remoteOAppEID}, {remoteOAppAddress})
        adapter.setPeer(eidReceiver, addressToBytes32(address(receiver)));
        receiver.setPeer(eidAdapter, addressToBytes32(address(adapter)));
    }
}

/** MOCKS */

/// Uber simple OApp that just sets a flag when it receives a message
/// useful for testing messages make it across, nothing else
contract OAppMockReceiver is OApp {
    bool public received;

    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal override {
        received = true;
    }

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) {}
}
