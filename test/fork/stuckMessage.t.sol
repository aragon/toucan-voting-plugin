// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {IOAppCore} from "@lz-oapp/OAppCore.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IToucanRelayMessage} from "@interfaces/IToucanRelayMessage.sol";
import {IToucanVoting} from "@toucan-voting/IToucanVoting.sol";

import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
import {ToucanReceiver, IToucanReceiverEvents} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";

import {TestHelpers} from "test/helpers/TestHelpers.sol";
import {MockLzEndpointMinimal} from "@mocks/MockLzEndpoint.sol";
import {DAO, createTestDAO} from "@mocks/MockDAO.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanProposal} from "@mocks/MockToucanVoting.sol";

import {console2 as console} from "forge-std/console2.sol";
import "@libs/TallyMath.sol";

import {deployToucanReceiver, deployMockToucanReceiver, deployMockToucanProposal} from "@utils/deployers.sol";
import "@utils/converters.sol";

contract ToucanReceiverStuckMessage is TestHelpers, IVoteContainer, IToucanReceiverEvents {
    using TallyMath for Tally;
    ToucanReceiver receiver = ToucanReceiver(payable(0xA52bEC62C3CA39d999778D671B5024CB7ef7E0a0));

    ILayerZeroEndpointV2 lzEndpoint =
        ILayerZeroEndpointV2(0x6EDCE65403992e310A62460808c4b910D972f10f);

    function test_whyMessageIsStuck() public {
        // encode valid params
        Tally memory votes = Tally(0, 1.05e22, 3e21);

        Origin memory origin = Origin(
            40232,
            addressToBytes32(0x65991B62B5067c1B4941E6F6A97add0e45280a3A),
            18
        );

        IToucanRelayMessage.ToucanVoteMessage memory message = IToucanRelayMessage
            .ToucanVoteMessage({
                votes: votes,
                votingChainId: 11155420, // block.chainid
                proposalRef: 154779696380424897416400549484501486953112152826972991694188353312700
            });

        // it says we dont have enough voting power
        ERC20Votes token = ERC20Votes(address(receiver.governanceToken()));

        // get the proposal
        IToucanVoting.ProposalParameters memory params = receiver.getProposalParams(5);

        // check the voting power
        uint votingPower = token.getPastVotes(address(receiver), params.snapshotBlock);

        console.log("voting power", votingPower);
        console.log("snapshot block", params.snapshotBlock);
        console.log("voting token", address(token));

        bool hasEnoughVotingPower = votingPower >= message.votes.sum();
        console.log("has enough voting power", hasEnoughVotingPower);

        // prank the endpoint so we can call lzReceive directly:
        vm.startPrank(address(lzEndpoint));
        {
            receiver.lzReceive(origin, bytes32(0x0), abi.encode(message), address(0), bytes(""));
        }
        vm.stopPrank();
    }
}
