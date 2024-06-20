// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {IToucanRelayMessage, ToucanRelay, MessagingFee, OptionsBuilder} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

import "forge-std/Test.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {deployMockToucanRelayLzMock, MockToucanRelayLzMock} from "@utils/deployers.sol";
import {addressToBytes32} from "@utils/converters.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";

import {ToucanRelayBaseTest} from "./ToucanRelayBase.t.sol";

// here we mock some of the layerZero functions to test exclusively the contract logic
// actual xchain tests should be done in integration testing
contract TestToucanRelayDispatch is ToucanRelayBaseTest {
    using TallyMath for Tally;
    using OverflowChecker for Tally;
    using ProposalIdCodec for uint256;
    using OptionsBuilder for bytes;

    function setUp() public override {
        super.setUp();

        relay = deployMockToucanRelayLzMock({
            _token: address(token),
            _lzEndpoint: address(lzEndpoint),
            _dao: address(dao)
        });

        dao.grant({
            _who: address(this),
            _where: address(relay),
            _permissionId: relay.OAPP_ADMINISTRATOR_ID()
        });
    }

    function testFuzz_quote(uint _proposalId, uint32 _dstEid, uint128 _gasLimit) public view {
        ToucanRelay.LzSendParams memory expectedParams = ToucanRelay.LzSendParams({
            dstEid: _dstEid,
            gasLimit: _gasLimit,
            fee: MessagingFee(100, 0),
            options: OptionsBuilder.newOptions().addExecutorLzReceiveOption({
                _gas: _gasLimit,
                _value: 0
            })
        });

        ToucanRelay.LzSendParams memory params = relay.quote(_proposalId, _dstEid, _gasLimit);

        assertEq(keccak256(abi.encode(params)), keccak256(abi.encode(expectedParams)));
    }

    function testFuzz_revertsIfCannotDispatch(
        uint _proposalId,
        ToucanRelay.LzSendParams memory _params
    ) public {
        // this requires the correct mock
        (bool success, ) = address(relay).call(
            abi.encodeWithSignature("setAllowDispatch(bool)", (false))
        );

        assertTrue(success, "setAllowDispatch failed");

        bytes memory revertData = abi.encodeWithSelector(
            ToucanRelay.CannotDispatch.selector,
            _proposalId,
            ToucanRelay.ErrReason.None
        );

        vm.expectRevert(revertData);
        relay.dispatchVotes(_proposalId, _params);
    }

    function testFuzz_emitsEventOnDispatch(
        uint _proposalId,
        ToucanRelay.LzSendParams memory _params,
        Tally memory _votes,
        address _peerAddress
    ) public {
        vm.assume(_peerAddress != address(0));
        // force the fee to be 100 in native only
        _params.fee = MessagingFee(100, 0);

        relay.setPeer(_params.dstEid, addressToBytes32(_peerAddress));

        // this requires the correct mock
        (bool success, ) = address(relay).call(
            abi.encodeWithSignature("setAllowDispatch(bool)", (true))
        );

        assertTrue(success, "setAllowDispatch failed");

        relay.setProposalState(_proposalId, _votes);

        vm.expectEmit(true, false, false, true);
        emit VotesDispatched(_proposalId, _votes);
        relay.dispatchVotes{value: 100}(_proposalId, _params);

        // check the state sent was as expected
        MockToucanRelayLzMock.LzSendReceived memory receipt = MockToucanRelayLzMock(address(relay))
            .getLzSendReceived();

        assertEq(receipt.dstEid, _params.dstEid);
        assertEq(keccak256(abi.encode(receipt.fee)), keccak256(abi.encode(_params.fee)));
        assertEq(receipt.refundAddress, relay.refundAddress(_params.dstEid));
        assertEq(receipt.options, _params.options);

        bytes memory expectedMessage = abi.encode(
            IToucanRelayMessage.ToucanVoteMessage({
                votingChainId: relay.chainId(),
                proposalId: _proposalId,
                votes: _votes
            })
        );

        assertEq(keccak256(receipt.message), keccak256(expectedMessage));
    }
}
