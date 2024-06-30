// /*
// DAO:  0xD14b1321fc6617AB674C559B4F3aC1bc0E34Fb4A
//   Token:  0x9edb9D5911e4486016cABa2e3B7e4fF0ca4AF814
//   Adapter:  0x45A75F35Fe9f5f12B04b4ec45B24Af3b867a35B5
//   Receiver:  0xDb44bC4F0c356751C1439e891f75A73B01a5dbc0
//   Plugin:  0x02987652faD5c3eb6021fb229659a9Cc57655E97
// Jordaniza — Today at 2:52 PM
// Voting Chain:
//   Bridge:  0x103C5DBc75EE122e8739094845FdaC1d4217b861
//   Relay:  0x02987652faD5c3eb6021fb229659a9Cc57655E97
//   DAO:  0xD14b1321fc6617AB674C559B4F3aC1bc0E34Fb4A
//   Token:  0x9edb9D5911e4486016cABa2e3B7e4fF0ca4AF814
// */

// /*
// v2 

//   DAO:  0x8B939dBF6d0836435a05f213e4A356f924Bf52C4
//   Token:  0x2A0D2AdAEb061f757B014B13Bf5D3e80Da805b2b
//   Adapter:  0xd07997230dF3e2b9e16EFe82101D98B4138327d2
//   Receiver:  0x1F6D879f06AAFC302a68101420ACe6C9f9968955
//   Plugin:  0x8EF6Ae17090F92357914Bc97DAD7E81677dC2F00

//     Running Voting Chain
//   Contracts deployed:
//   Voting Chain:
//   Bridge:  0xB1E29B5fC78B9639de6be4420BE433154C152522
//   Relay:  0x2A0D2AdAEb061f757B014B13Bf5D3e80Da805b2b
//   DAO:  0xFd4672D3975F862F4B9fc7d08b2ba8E68EAc9938
//   Token:  0x728614C2f068d10D2F2D0Aaf0F92631947fee642


// v3

//   Execution Chain:
//   DAO:  0xd08Da5577874Bd1E7931699F42eF7C2F5De6c1c8
//   Token:  0xfA8Df779f6bCC0aEc166F3DAa608B0674224e6cf
//   Adapter:  0x53a7Cc798C605CBC06409D3310dd5E3E2b87A1AA
//   Receiver:  0x6EB1dBD2701742a8CeACB1E1505ba7Dd3408464b
//   Plugin:  0x7FB8C307D2c8e0248D8477Cc501ED2DaBb23AA14

//   Voting Chain:
//   Bridge:  0x09FCD9f2863955826669D85AEb969a493E39B0dC
//   Relay:  0xf82FA1a0b4353B4a3BB4e9EB3D55598f9ab13298
//   DAO:  0x88Bf11e0b99C1bBaB8797fAbfbD2705d194046c0
//   Token:  0xe652A170E6C9675D516858C1F88a5F46A6A48cc2

// */

// // // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.17;

// import {Test, console2} from "forge-std/Test.sol";
// import {Script} from "forge-std/Script.sol";

// // external contracts
// import {OApp} from "@lz-oapp/OApp.sol";
// import {OFT} from "@lz-oft/OFT.sol";
// import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
// import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
// import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
// import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

// // aragon contracts
// import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
// import {DAO} from "@aragon/osx/core/dao/DAO.sol";
// import {ProxyLib} from "@libs/ProxyLib.sol";
// import {GovernanceERC20} from "@toucan-voting/ERC20/governance/GovernanceERC20.sol";
// import {ToucanVoting as ToucanVoting} from "@toucan-voting/ToucanVoting.sol";
// import {IToucanVoting, IVoteContainer} from "@toucan-voting/IToucanVoting.sol";

// import {DAO} from "@aragon/osx/core/dao/DAO.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// // external test utils
// import "forge-std/console2.sol";

// // internal contracts
// import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
// import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
// import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

// import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
// import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
// import {ProposalIdCodec} from "@libs/ProposalRefEncoder.sol";

// // internal test utils
// import "@utils/converters.sol";
// import "@utils/deployers.sol";
// import "forge-std/console2.sol";

// import {MockDAOSimplePermission as MockDAO} from "test/mocks/MockDAO.sol";
// import {AragonTest} from "test/base/AragonTest.sol";

// abstract contract BaseContracts {
//     using OptionsBuilder for bytes;
//     using ProxyLib for address;
//     using ProposalIdCodec for uint256;

//     struct Execution {
//         address dao;
//         address token;
//         address adapter;
//         address receiver;
//         address plugin;
//     }

//     Execution _execution =
//         Execution({
//             dao: 0xD14b1321fc6617AB674C559B4F3aC1bc0E34Fb4A,
//             token: 0x9edb9D5911e4486016cABa2e3B7e4fF0ca4AF814,
//             adapter: 0x45A75F35Fe9f5f12B04b4ec45B24Af3b867a35B5,
//             receiver: 0xDb44bC4F0c356751C1439e891f75A73B01a5dbc0,
//             plugin: 0x02987652faD5c3eb6021fb229659a9Cc57655E97
//         });

//     Execution _execution_v2 =
//         Execution({
//             dao: 0x8B939dBF6d0836435a05f213e4A356f924Bf52C4,
//             token: 0x2A0D2AdAEb061f757B014B13Bf5D3e80Da805b2b,
//             adapter: 0xd07997230dF3e2b9e16EFe82101D98B4138327d2,
//             receiver: 0x1F6D879f06AAFC302a68101420ACe6C9f9968955,
//             plugin: 0x8EF6Ae17090F92357914Bc97DAD7E81677dC2F00
//         });

//     Execution _execution_v3 =
//         Execution({
//             dao: 0xd08Da5577874Bd1E7931699F42eF7C2F5De6c1c8,
//             token: 0xfA8Df779f6bCC0aEc166F3DAa608B0674224e6cf,
//             adapter: 0x53a7Cc798C605CBC06409D3310dd5E3E2b87A1AA,
//             receiver: 0x6EB1dBD2701742a8CeACB1E1505ba7Dd3408464b,
//             plugin: 0x7FB8C307D2c8e0248D8477Cc501ED2DaBb23AA14
//         });

//     struct Voting {
//         address bridge;
//         address relay;
//         address dao;
//         address token;
//     }

//     Voting _voting =
//         Voting({
//             bridge: 0x103C5DBc75EE122e8739094845FdaC1d4217b861,
//             relay: 0x02987652faD5c3eb6021fb229659a9Cc57655E97,
//             dao: 0xD14b1321fc6617AB674C559B4F3aC1bc0E34Fb4A,
//             token: 0x9edb9D5911e4486016cABa2e3B7e4fF0ca4AF814
//         });

//     Voting _voting_v2 =
//         Voting({
//             bridge: 0xB1E29B5fC78B9639de6be4420BE433154C152522,
//             relay: 0x2A0D2AdAEb061f757B014B13Bf5D3e80Da805b2b,
//             dao: 0xFd4672D3975F862F4B9fc7d08b2ba8E68EAc9938,
//             token: 0x728614C2f068d10D2F2D0Aaf0F92631947fee642
//         });

//     Voting _voting_v3 =
//         Voting({
//             bridge: 0x09FCD9f2863955826669D85AEb969a493E39B0dC,
//             relay: 0xf82FA1a0b4353B4a3BB4e9EB3D55598f9ab13298,
//             dao: 0x88Bf11e0b99C1bBaB8797fAbfbD2705d194046c0,
//             token: 0xe652A170E6C9675D516858C1F88a5F46A6A48cc2
//         });

//     struct Contracts {
//         Execution ex;
//         Voting vo;
//     }

//     Contracts contracts = Contracts(_execution_v3, _voting_v3);

//     struct LzChain {
//         uint32 eid;
//         address endpoint;
//     }

//     // agents
//     address deployer;

//     address ADMIN = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
//     address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;

//     // me: deploying with throwaway eoa.
//     address executionVoter = ADMIN;
//     address votingVoter = JUAR;

//     LzChain SEPOLIA = LzChain(40161, 0x6EDCE65403992e310A62460808c4b910D972f10f);
//     LzChain ARBITRUM_SEPOLIA = LzChain(40231, 0x6EDCE65403992e310A62460808c4b910D972f10f);

//     // execution chain
//     uint32 EID_EXECUTION_CHAIN = SEPOLIA.eid;

//     address daoExecutionChain = contracts.ex.dao;
//     GovernanceERC20 tokenExecutionChain = GovernanceERC20(contracts.ex.token);
//     GovernanceOFTAdapter adapter = GovernanceOFTAdapter(contracts.ex.adapter);
//     ToucanReceiver receiver = ToucanReceiver(payable(contracts.ex.receiver));
//     ToucanVoting plugin = ToucanVoting(contracts.ex.plugin);
//     address layerZeroEndpointExecutionChain = SEPOLIA.endpoint;

//     // voting chain
//     uint32 EID_VOTING_CHAIN = ARBITRUM_SEPOLIA.eid;

//     address daoVotingChain = contracts.vo.dao;
//     GovernanceERC20VotingChain tokenVotingChain = GovernanceERC20VotingChain(contracts.vo.token);
//     OFTTokenBridge bridge = OFTTokenBridge(contracts.vo.bridge);
//     ToucanRelay relay = ToucanRelay(contracts.vo.relay);
//     address layerZeroEndpointVotingChain = ARBITRUM_SEPOLIA.endpoint;

//     // cash they get in governance tokens
//     // uint constant INITIAL_MINT = 100 ether;

//     uint sendQty = 5_000 ether;
//     // uint total = INITIAL_MINT;
//     // uint remaining = sendQty - sendQty;

//     // voting params
//     uint32 constant SUPPORT_THRESHOLD = 1;
//     uint32 constant MIN_PARTICIPATION = 1;
//     uint64 constant MIN_DURATION = 3600;
//     uint constant MIN_PROPOSER_VOTING_POWER = 1;
//     ToucanVoting.VotingMode constant MODE = IToucanVoting.VotingMode.VoteReplacement;

//     uint256 PROPOSAL_2 =
//         64664270401656640812369971395693734794954279304534741224351048272538191464264;
//     uint256 PROPOSAL_3 =
//         64664270401656640812369971395693734794954279304534741263531932338751116349332;

//     function createProposal(uint _votesFor) public returns (uint256 proposalId) {
//         IDAO.Action[] memory actions = new IDAO.Action[](1);
//         actions[0] = IDAO.Action({
//             to: address(this),
//             value: 0,
//             data: abi.encodeWithSignature("test_itWorks()")
//         });
//         ToucanVoting.Tally memory tally = IVoteContainer.Tally({abstain: 0, yes: _votesFor, no: 0});
//         return
//             plugin.createProposal({
//                 _metadata: bytes("0x"),
//                 _actions: actions,
//                 _allowFailureMap: 0,
//                 _startDate: 0, // start now
//                 _endDate: uint32(block.timestamp + 1 days),
//                 _tryEarlyExecution: false,
//                 _votes: tally
//             });
//     }

//     function _bridgeTokensToL1(uint _quantity, uint128 _gas, address _who) public {
//         bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);
//         SendParam memory sendParams = SendParam({
//             dstEid: EID_EXECUTION_CHAIN,
//             to: addressToBytes32(_who),
//             amountLD: _quantity,
//             minAmountLD: _quantity,
//             extraOptions: options,
//             composeMsg: bytes(""),
//             oftCmd: bytes("")
//         });

//         // fetch a quote
//         MessagingFee memory msgFee = bridge.quoteSend(sendParams, false);

//         // send the message
//         tokenVotingChain.approve(address(bridge), _quantity);
//         bridge.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
//     }

//     function _bridgeTokensToL2(uint _quantity, uint128 _gas, address _who) public {
//         bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, 0);
//         SendParam memory sendParams = SendParam({
//             dstEid: EID_VOTING_CHAIN,
//             to: addressToBytes32(_who),
//             amountLD: _quantity,
//             minAmountLD: _quantity,
//             extraOptions: options,
//             composeMsg: bytes(""),
//             oftCmd: bytes("")
//         });

//         // fetch a quote
//         MessagingFee memory msgFee = adapter.quoteSend(sendParams, false);

//         // send the message
//         tokenExecutionChain.approve(address(adapter), _quantity);
//         adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
//     }

//     function _dispatchVotes(uint proposal) internal {
//         uint128 gasLimit = 250_000;
//         ToucanRelay.LzSendParams memory params = relay.quote(
//             proposal,
//             EID_EXECUTION_CHAIN,
//             gasLimit
//         );
//         relay.dispatchVotes{value: params.fee.nativeFee}(proposal, params);
//     }

//     function _connectOApps() internal {
//         if (_executionChain()) {
//             _connectOApps_executionChain();
//         } else {
//             _connectOApps_votingChain();
//         }
//     }

//     function _executionChain() internal view virtual returns (bool);

//     function _connectOApps_executionChain() internal {
//         // the oftadapter and the bridge have a bidrectional relationship
//         adapter.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(bridge)));
//         receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
//     }

//     function _connectOApps_votingChain() internal {
//         bridge.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(adapter)));
//         relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
//     }

//     function getProposalTally(
//         uint256 _proposalId
//     ) internal view returns (IVoteContainer.Tally memory tally) {
//         (, , , tally, , ) = plugin.getProposal(_proposalId);
//     }
// }

// contract TestDemoOffsite is BaseContracts, Test {
//     using OptionsBuilder for bytes;
//     using ProxyLib for address;
//     using ProposalIdCodec for uint256;

//     uint proposalId;

//     function setUp() public {
//         _addLabels();
//     }

//     function test_demoOffsite() public {
//         // should be done in advance!
//         // vm.startPrank(ADMIN);
//         // {
//         //     _connectOApps();
//         // }
//         // vm.stopPrank();

//         vm.startPrank(executionVoter);
//         {
//             if (_executionChain()) {
//                 _bridgeTokensToL2(sendQty, 250_000, executionVoter);
//                 // proposalId = createProposal(5 ether /*votesFor*/);
//                 // console2.log("proposalId", proposalId);
//             } else {
//                 uint proposal = PROPOSAL_3;
//                 relay.vote(proposal, IVoteContainer.Tally({abstain: 0, yes: 1 ether, no: 0}));
//                 _dispatchVotes(proposal);
//             }
//         }
//         vm.stopPrank();
//     }

//     function _grantLambos() internal {
//         vm.deal(votingVoter, 1000 ether);
//         vm.deal(executionVoter, 1000 ether);
//     }

//     function _addLabels() internal {
//         vm.label(executionVoter, "EXECUTION_VOTER");
//         vm.label(votingVoter, "VOTING_VOTER");

//         vm.label(daoExecutionChain, "DAO_EXECUTION_CHAIN");
//         vm.label(daoVotingChain, "DAO_VOTING_CHAIN");

//         vm.label(address(tokenVotingChain), "TOKEN_VOTING_CHAIN");
//         vm.label(address(tokenExecutionChain), "TOKEN_EXECUTION_CHAIN");

//         vm.label(layerZeroEndpointExecutionChain, "LZ_ENDPOINT_EXECUTION_CHAIN");
//         vm.label(layerZeroEndpointVotingChain, "LZ_ENDPOINT_VOTING_CHAIN");
//     }

//     function _executionChain() internal pure override returns (bool) {
//         return false;
//     }
// }

// contract ExecuteDemoOffsite is BaseContracts, Script {
//     uint proposalId;

//     modifier broadcast() {
//         uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
//         deployer = vm.addr(deployerPrivateKey);

//         vm.startBroadcast(deployer);
//         _;
//         vm.stopBroadcast();
//     }

//     function run() public broadcast {
//         // _connectOApps();
//         if (_executionChain()) {
//             _bridgeTokensToL2(sendQty, 250_000, executionVoter);
//             // best to break these up a bit to ensure block timestamp doesn't box you out
//             // proposalId = createProposal(5 ether /*votesFor*/);
//             // console2.log("proposalId", proposalId);
//         } else {
//             uint proposal = 57770177681449521531879167270960685756592616423179422297141710732427487098944;

//             // uint proposal = PROPOSAL_3;
//             relay.vote(proposal, IVoteContainer.Tally({abstain: 0, yes: 100 ether, no: 300 ether}));
//             _dispatchVotes(proposal);
//         }
//     }

//     function _executionChain() internal view override returns (bool) {
//         string memory result = vm.envString("EXECUTION_OR_VOTING");
//         if (keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked("EXECUTION"))) {
//             return true;
//         } else if (keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked("VOTING"))) {
//             return false;
//         } else {
//             revert(
//                 "Invalid env variable EXECUTION_OR_VOTING, must be either 'EXECUTION' or 'VOTING'"
//             );
//         }
//     }

//     /**
//      * deploy:
//      * Deploy contracts
//      *
//      * script:
//      * Wire Oapps
//      * Bridge tokens
//      * Connect addresses on aragonette
//      * Create proposal
//      * Vote
//      * Dispatch
//      */
// }
