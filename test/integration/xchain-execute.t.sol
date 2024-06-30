// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO, PermissionManager} from "@aragon/osx/core/dao/DAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper} from "@lz-oapp-test/TestHelper.sol";

// internal contracts
import {ProposalIdCodec} from "@libs/ProposalRefEncoder.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

import {ActionRelay} from "@execution-chain/crosschain/ActionRelay.sol";
import {AdminXChain} from "@voting-chain/crosschain/AdminXChain.sol";

// internal test utils
import "@utils/converters.sol";
import "forge-std/console2.sol";

import {MockDAOSimplePermission as MockDAO} from "test/mocks/MockDAO.sol";
import {AragonTest} from "test/base/AragonTest.sol";

import "@utils/deployers.sol";

uint256 constant _EVM_VOTING_CHAIN = 420;

/**
 * This contract tests the following workflow:
 * 1. Setup XChainAdmin on DAO_V
 * 2. Setup Relayer on DAO_E
 * 3. Allowlist DAO_E as Origin for DAO_V
 * 4. Quote bridging fee to DAO_V for 2 actions
 * 5. Execute proposal on DAO_E
 * 6. Should update DAO_V
 */
contract TestXChainExecute is TestHelper, AragonTest {
    using OptionsBuilder for bytes;
    using ProxyLib for address;
    using ProposalIdCodec for uint256;

    // crosschain
    uint constant PROPOSAL_ID = 1234;
    uint128 constant GAS_LIMIT = 100000;

    // execution chain
    uint32 constant EID_EXECUTION_CHAIN = 1;
    uint256 constant EVM_EXECUTION_CHAIN = 137;

    address layerZeroEndpointExecutionChain;
    DAO daoExecutionChain;
    ActionRelay relayer;

    // voting chain
    uint32 constant EID_VOTING_CHAIN = 2;
    uint256 constant EVM_VOTING_CHAIN = _EVM_VOTING_CHAIN;

    address layerZeroEndpointVotingChain;
    DAO daoVotingChain;
    AdminXChain admin;

    // function setUp() public override {
    //     // warp to genesis
    //     vm.warp(1);
    //     vm.roll(1);
    //     super.setUp();
    //     _initializeLzEndpoints();
    //     _deployExecutionChain();
    //     _deployVotingChain();
    //     _connectOApps();
    //     _addLabels();
    //     _grantLambos();
    // }

    // function testXChainProposals() public {
    //     revert("FIX THIS");
    //     // the proposal we want to send across will uninstall the admin on the voting
    //     IDAO.Action[] memory actions = _createUninstallationProposal();
    //     // send through the dao
    //     daoExecutionChain.execute(bytes32(PROPOSAL_ID), actions, 0);
    //     // move the packet across
    //     verifyRelayedProposal();
    // }

    // function _grantLambos() public {
    //     // give the DAO plenty of cash to pay for xchain fees
    //     vm.deal(address(daoExecutionChain), 1000 ether);
    // }

    // function _createUninstallationProposal() public view returns (IDAO.Action[] memory) {
    //     IDAO.Action[] memory innerActions = new IDAO.Action[](2);

    //     // // these re the inner actions
    //     // innerActions[0] = IDAO.Action({
    //     //     to: address(daoVotingChain),
    //     //     data: abi.encodeCall(
    //     //         daoVotingChain.revoke,
    //     //         (
    //     //             /* where */ address(daoVotingChain),
    //     //             /* who */ address(admin),
    //     //             /* permissionId */ daoVotingChain.EXECUTE_PERMISSION_ID()
    //     //         )
    //     //     ),
    //     //     value: 0
    //     // });

    //     // innerActions[1] = IDAO.Action({
    //     //     to: address(daoVotingChain),
    //     //     data: abi.encodeCall(
    //     //         daoVotingChain.revoke,
    //     //         (
    //     //             /* where */ address(admin),
    //     //             /* who */ address(relayer),
    //     //             /* permissionId */ admin.XCHAIN_EXECUTE_PERMISSION_ID()
    //     //         )
    //     //     ),
    //     //     value: 0
    //     // });

    //     // the actual action is passing the above to the relayer

    //     // first we need a quote
    //     ActionRelay.LzSendParams memory params = relayer.quote(
    //         PROPOSAL_ID,
    //         innerActions,
    //         0, // allowFailureMap
    //         EID_VOTING_CHAIN,
    //         GAS_LIMIT
    //     );

    //     // now we can create the execute action
    //     IDAO.Action[] memory actions = new IDAO.Action[](1);

    //     actions[0] = IDAO.Action({
    //         to: address(relayer),
    //         data: abi.encodeCall(
    //             relayer.relayActions,
    //             (
    //                 PROPOSAL_ID,
    //                 innerActions,
    //                 0, // allowFailureMap
    //                 params
    //             )
    //         ),
    //         // this is super important, it's not a zero value
    //         // transfer because the layer zero endpoint will
    //         // expect a fee from the DAO
    //         value: params.fee.nativeFee
    //     });

    //     return actions;
    // }

    // function verifyRelayedProposal() public {
    //     verifyPackets(EID_VOTING_CHAIN, address(admin));
    // }

    // function _addLabels() internal {
    //     vm.label(address(daoExecutionChain), "DAO_EXECUTION_CHAIN");
    //     vm.label(address(daoVotingChain), "DAO_VOTING_CHAIN");

    //     vm.label(layerZeroEndpointExecutionChain, "LZ_ENDPOINT_EXECUTION_CHAIN");
    //     vm.label(layerZeroEndpointVotingChain, "LZ_ENDPOINT_VOTING_CHAIN");

    //     vm.label(address(relayer), "RELAYER");
    //     vm.label(address(admin), "ADMIN");
    // }

    // // call this first
    // function _initializeLzEndpoints() internal {
    //     setUpEndpoints(2, LibraryType.SimpleMessageLib);

    //     layerZeroEndpointExecutionChain = endpoints[EID_EXECUTION_CHAIN];
    //     layerZeroEndpointVotingChain = endpoints[EID_VOTING_CHAIN];
    // }

    // function _deployExecutionChain() internal {
    //     // setup the dao
    //     daoExecutionChain = createMockDAO(address(this));

    //     // deploy the relayer and connect to the dao on the execution chain
    //     relayer = deployActionRelay(layerZeroEndpointExecutionChain, address(daoExecutionChain));

    //     // grant the DAO the ability to call the relayProposal function
    //     daoExecutionChain.grant({
    //         _who: address(daoExecutionChain),
    //         _where: address(relayer),
    //         _permissionId: relayer.XCHAIN_ACTION_RELAYER_ID()
    //     });

    //     // give this contract the ability to call execute on the DAO for testing purposes
    //     // this would be a plugin in the real world
    //     daoExecutionChain.grant({
    //         _who: address(this),
    //         _where: address(daoExecutionChain),
    //         _permissionId: daoExecutionChain.EXECUTE_PERMISSION_ID()
    //     });
    // }

    // function _deployVotingChain() internal {
    //     daoVotingChain = createMockDAO();

    //     // deploy the xchainadmin
    //     admin = deployAdminXChain({
    //         _dao: address(daoVotingChain),
    //         _lzEndpoint: layerZeroEndpointVotingChain
    //     });

    //     PermissionLib.MultiTargetPermission[]
    //         memory permissions = new PermissionLib.MultiTargetPermission[](3);

    //     // Grant the cross chain permission: the relayer on the execution chain can execute proposals on the voting chain.
    //     permissions[0] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Grant,
    //         where: address(admin),
    //         who: address(relayer),
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: admin.XCHAIN_EXECUTE_PERMISSION_ID()
    //     });

    //     // grant the ability to the admin to call execute on the dao
    //     permissions[1] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Grant,
    //         where: address(daoVotingChain),
    //         who: address(admin),
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: daoVotingChain.EXECUTE_PERMISSION_ID()
    //     });

    //     // give the dao root on itself
    //     permissions[2] = PermissionLib.MultiTargetPermission({
    //         operation: PermissionLib.Operation.Grant,
    //         where: address(daoVotingChain),
    //         who: address(daoVotingChain),
    //         condition: PermissionLib.NO_CONDITION,
    //         permissionId: daoVotingChain.ROOT_PERMISSION_ID()
    //     });

    //     // apply the permissions
    //     daoVotingChain.applyMultiTargetPermissions(permissions);
    // }

    // function _connectOApps() internal {
    //     relayer.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(admin)));
    //     admin.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(relayer)));
    // }
}
