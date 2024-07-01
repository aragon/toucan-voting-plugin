// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.17;

// // external contracts
// import {OApp} from "@lz-oapp/OApp.sol";
// import {OFT} from "@lz-oft/OFT.sol";
// import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
// import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
// import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
// import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
// import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// // aragon contracts
// import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
// import {DAO} from "@aragon/osx/core/dao/DAO.sol";
// import {Admin, AdminSetup} from "@aragon/admin/AdminSetup.sol";

// // external test utils
// import "forge-std/console2.sol";
// import {TestHelper as LzTestHelper} from "@lz-oapp-test/TestHelper.sol";

// // own the libs
// import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
// import {ProxyLib} from "@libs/ProxyLib.sol";
// import {TallyMath} from "@libs/TallyMath.sol";

// // internal contracts
// import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

// /// execution chain
// import {ToucanVoting, ToucanVotingSetup, IToucanVoting, GovernanceERC20, GovernanceWrappedERC20} from "@toucan-voting/ToucanVotingSetup.sol";
// import {ToucanReceiver, ToucanReceiverSetup, GovernanceOFTAdapter} from "@execution-chain/setup/ToucanReceiverSetup.sol";

// /// voting chain
// import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
// import {ToucanRelay, ToucanRelaySetup, OFTTokenBridge} from "@voting-chain/setup/ToucanRelaySetup.sol";
// import {AdminXChain, AdminXChainSetup} from "@voting-chain/setup/AdminXChainSetup.sol";

// // utils
// import "@utils/converters.sol";
// import "@utils/deployers.sol";

// // test utils
// import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
// import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
// import "@helpers/OSxHelpers.sol";
// import "forge-std/console2.sol";

// /**
//  * An E2E test of the entire Toucan voting system.
//  * This covers the following:
//  *
//  * - Deploying the contracts using plugin setups
//  * - Bridging tokens
//  *  - forward
//  *  - back
//  * - Creating a proposal on the voting plugin
//  * - Voting on the proposal, remote x 2 chains
//  *  - Simulating a brige delay
//  *  - Sending an invalid proposal ref
//  * - Changing to a new voting plugin, and ensuring votes are recorded accordingly
//  * - Voting on the proposal, locally
//  * - Executing the crosschain proposal to upgrade the relay and to set a permission on the admin
//  *
//  */
// contract TestSetupE2EBase is LzTestHelper, IVoteContainer {
//     using OptionsBuilder for bytes;
//     using ProxyLib for address;
//     using ProposalRefEncoder for uint256;
//     using TallyMath for Tally;

//     struct ChainBase {
//         string chainName;
//         // layer zero
//         uint32 eid;
//         uint256 chainid;
//         address lzEndpoint;
//         // OSX
//         DAO dao;
//         MockPluginSetupProcessor psp;
//         MockDAOFactory daoFactory;
//         // deployer
//         address deployer;
//         // we need admin to access the DAO
//         AdminSetup adminSetup;
//         Admin admin;
//     }

//     struct VotingChain {
//         ChainBase base;
//         // contracts
//         GovernanceERC20VotingChain token;
//         MockToucanRelay relay;
//         ToucanVoting plugin;
//         AdminXChain adminXChain;
//         // setups
//         ToucanVotingSetup votingSetup;
//         AdminXChainSetup adminXChainSetup;
//         // agents
//         address voter;
//     }

//     /// deploy the base contracts
//     function _initChainBase(
//         string memory _chainName,
//         uint256 _chainid,
//         address _deployer
//     ) internal pure returns (ChainBase memory base) {
//         base.chainName = _chainName;
//         base.chainid = _chainid;
//         base.deployer = _deployer;
//     }

//     function _deployOSX(ChainBase storage base) internal {
//         // deploy the mock PSP with the admin plugin
//         base.adminSetup = new AdminSetup();
//         base.psp = new MockPluginSetupProcessor(address(base.adminSetup));
//         base.daoFactory = new MockDAOFactory(base.psp);
//     }

//     function _deployLayerZero(
//         ChainBase storage executionChain,
//         ChainBase[] storage votingChains
//     ) internal {
//         uint8 numChains = uint8(votingChains.length);
//         setUpEndpoints(1 + numChains, LibraryType.UltraLightNode);

//         executionChain.lzEndpoint = endpoints[0];
//         executionChain.eid = 0;

//         for (uint8 i = 0; i < numChains; i++) {
//             votingChains[i].lzEndpoint = endpoints[i + 1];
//             votingChains[i].eid = i + 1;
//         }
//     }

//     function _deployDAOAndAdmin(ChainBase storage base) internal {
//         // use the OSx DAO factory with the Admin Plugin
//         bytes memory data = abi.encode(base.deployer);
//         base.dao = base.daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

//         // nonce 0 is something?
//         // nonce 1 is implementation contract
//         // nonce 2 is the admin contract behind the proxy
//         base.admin = Admin(computeAddress(address(base.adminSetup), 2));
//         assertEq(base.admin.isMember(base.deployer), true, "trustedDeployer should be a member");
//     }
// }

// contract TestSetupExecutionChainE2E is TestSetupE2EBase {
//     struct ExecutionChain {
//         ChainBase base;
//         // contracts
//         GovernanceERC20 token;
//         GovernanceOFTAdapter adapter;
//         ToucanReceiver receiver;
//         ActionRelay actionRelay;
//         ToucanVoting voting;
//         // setups
//         ToucanReceiverSetup receiverSetup;
//         ToucanVoting votingSetup;
//         // permissions
//         PermissionLib.MultiTargetPermission[] receiverPermissions;
//         PermissionLib.MultiTargetPermission[] votingPermissions;
//         // agents
//         address voter;
//     }

//     function _prepareSetupToucanVoting(ExecutionChain storage chain) internal {
//         GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
//             new address[](1),
//             new uint256[](1)
//         );
//         mintSettings.receivers[0] = address(this);
//         mintSettings.amounts[0] = 0;

//         GovernanceERC20 baseToken = new GovernanceERC20(
//             IDAO(address(chain.base.dao)),
//             "Test Token",
//             "TT",
//             mintSettings
//         );

//         chain.votingSetup = new ToucanVotingSetup(
//             new ToucanVoting(),
//             baseToken,
//             new GovernanceWrappedERC20(
//                 IERC20Upgradeable(address(baseToken)),
//                 "Wrapped Test Token",
//                 "WTT"
//             )
//         );

//         // push to the PSP
//         chain.base.psp.queueSetup(address(chain.votingSetup));

//         // prep the data
//         IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
//             votingMode: IToucanVoting.VotingMode.VoteReplacement,
//             supportThreshold: 1e5,
//             minParticipation: 1e5,
//             minDuration: 1 days,
//             minProposerVotingPower: 1 ether
//         });

//         ToucanVotingSetup.TokenSettings memory tokenSettings = ToucanVotingSetup.TokenSettings({
//             addr: address(0),
//             symbol: "TT",
//             name: "TestToken"
//         });

//         mintSettings.receivers[0] = chain.voter;
//         mintSettings.amounts[0] = 1_000_000_000 ether;

//         bytes memory data = abi.encode(votingSettings, tokenSettings, mintSettings, false);

//         (
//             address votingPluginAddress,
//             IPluginSetup.PreparedSetupData memory votingPluginPreparedSetupData
//         ) = chain.base.psp.prepareInstallation(
//                 address(chain.base.dao),
//                 _mockPrepareInstallationParams(data)
//             );

//         // cannot write to storage from memory memory so just push here
//         for (uint256 i = 0; i < votingPluginPreparedSetupData.permissions.length; i++) {
//             chain.votingPermissions.push(votingPluginPreparedSetupData.permissions[i]);
//         }

//         chain.voting = ToucanVoting(votingPluginAddress);
//         address[] memory helpers = votingPluginPreparedSetupData.helpers;
//         chain.token = GovernanceERC20(helpers[0]);
//     }

//     function _prepareSetupReceiver(ExecutionChain storage chain) internal {
//         // deploy receiver and set it as next address for PSP to use
//         chain.receiverSetup = new ToucanReceiverSetup(
//             new ToucanReceiver(),
//             new GovernanceOFTAdapter(),
//             new ActionRelay()
//         );
//         chain.base.psp.queueSetup(address(chain.receiverSetup));

//         // prepare the installation
//         bytes memory data = abi.encode(address(chain.base.lzEndpoint), address(chain.voting));

//         (
//             address receiverPluginAddress,
//             IPluginSetup.PreparedSetupData memory receiverPluginPreparedSetupData
//         ) = chain.base.psp.prepareInstallation(
//                 address(chain.base.dao),
//                 _mockPrepareInstallationParams(data)
//             );

//         // cannot write to storage from memory memory so just push here
//         for (uint256 i = 0; i < receiverPluginPreparedSetupData.permissions.length; i++) {
//             chain.receiverPermissions.push(receiverPluginPreparedSetupData.permissions[i]);
//         }

//         chain.receiver = ToucanReceiver(payable(receiverPluginAddress));
//         address[] memory helpers = receiverPluginPreparedSetupData.helpers;
//         chain.adapter = GovernanceOFTAdapter(helpers[0]);
//         chain.actionRelay = ActionRelay(helpers[1]);
//     }

//     function _prepareUninstallAdmin(ExecutionChain storage chain) internal {
//         // psp will use the admin setup in next call
//         chain.base.psp.queueSetup(address(chain.base.adminSetup));

//         IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
//             plugin: address(chain.base.admin),
//             currentHelpers: new address[](0),
//             data: new bytes(0)
//         });

//         // prepare the uninstallation
//         PermissionLib.MultiTargetPermission[] memory permissions = chain
//             .base
//             .psp
//             .prepareUninstallation(
//                 address(chain.base.dao),
//                 _mockPrepareUninstallationParams(payload)
//             );

//         // cannot write to storage from memory memory so just push here
//         for (uint256 i = 0; i < permissions.length; i++) {
//             adminUninstallPermissions.push(permissions[i]);
//         }
//     }

//     function _applyInstallationsSetPeersRevokeAdmin(ExecutionChain storage chain) internal {
//         IDAO.Action[] memory actions = new IDAO.Action[](6);

//         // action 0: apply the tokenVoting installation
//         actions[0] = IDAO.Action({
//             to: address(chain.base.psp),
//             value: 0,
//             data: abi.encodeCall(
//                 chain.base.psp.applyInstallation,
//                 (
//                     address(chain.base.dao),
//                     _mockApplyInstallationParams(address(voting), votingPermissions)
//                 )
//             )
//         });

//         // action 1: apply the receiver installation
//         actions[1] = IDAO.Action({
//             to: address(chain.base.psp),
//             value: 0,
//             data: abi.encodeCall(
//                 chain.base.psp.applyInstallation,
//                 (
//                     address(chain.base.dao),
//                     _mockApplyInstallationParams(address(chain.base.receiver), receiverPermissions)
//                 )
//             )
//         });

//         // action 2,3,4: set the peers
//         actions[2] = IDAO.Action({
//             to: address(chain.base.receiver),
//             value: 0,
//             data: abi.encodeCall(receiver.setPeer, (remoteEid, addressToBytes32(remoteRelay)))
//         });

//         actions[3] = IDAO.Action({
//             to: address(actionRelay),
//             value: 0,
//             data: abi.encodeCall(
//                 chain.actionRelay.setPeer,
//                 (remoteEid, addressToBytes32(remoteXchainAdmin))
//             )
//         });

//         actions[4] = IDAO.Action({
//             to: address(adapter),
//             value: 0,
//             data: abi.encodeCall(adapter.setPeer, (remoteEid, addressToBytes32(remoteBridge)))
//         });

//         // action 5: uninstall the admin plugin
//         actions[5] = IDAO.Action({
//             to: address(chain.base.psp),
//             value: 0,
//             data: abi.encodeCall(
//                 chain.base.psp.applyUninstallation,
//                 (
//                     address(chain.base.dao),
//                     _mockApplyUninstallationParams(
//                         address(chain.base.admin),
//                         adminUninstallPermissions
//                     )
//                 )
//             )
//         });

//         // wrap the actions in grant/revoke root permissions
//         IDAO.Action[] memory wrappedActions = wrapGrantRevokeRoot(
//             dao,
//             address(chain.base.psp),
//             actions
//         );

//         // execute the actions
//         vm.startPrank(chain.base.deployer);
//         {
//             chain.base.admin.executeProposal({
//                 _metadata: "",
//                 _actions: wrappedActions,
//                 _allowFailureMap: 0
//             });
//         }
//         vm.stopPrank();
//     }
// }
