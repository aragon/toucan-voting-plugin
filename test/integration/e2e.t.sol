// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {Admin, AdminSetup} from "@aragon/admin/AdminSetup.sol";

// external test utils
import "forge-std/console2.sol";
import {TestHelper as LzTestHelper} from "@lz-oapp-test/TestHelper.sol";

// own the libs
import {ProposalRefEncoder} from "@libs/ProposalRefEncoder.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {TallyMath} from "@libs/TallyMath.sol";

// internal contracts
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

/// execution chain
import {ToucanVoting, ToucanVotingSetup, IToucanVoting, GovernanceERC20, GovernanceWrappedERC20} from "@toucan-voting/ToucanVotingSetup.sol";
import {ToucanReceiver, ToucanReceiverSetup, GovernanceOFTAdapter} from "@execution-chain/setup/ToucanReceiverSetup.sol";

/// voting chain
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay, ToucanRelaySetup, OFTTokenBridge} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {AdminXChain, AdminXChainSetup} from "@voting-chain/setup/AdminXChainSetup.sol";

// utils
import "@utils/converters.sol";
import "@utils/deployers.sol";

// test utils
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import "@helpers/OSxHelpers.sol";
import "forge-std/console2.sol";

/**
 * An E2E test of the entire Toucan voting system.
 * This covers the following:
 *
 * ✅ Deploying the contracts using plugin setups
 *  Bridging tokens
 *  ✅ forward
 *  - back
 *  ✅ Creating a proposal on the voting plugin
 *  ✅ Voting on the proposal,
 *   - remote x 2 chains
 *  - Simulating a brige delay
 *  - Sending an invalid proposal ref
 * - Changing to a new voting plugin, and ensuring votes are recorded accordingly
 * ✅ Voting on the proposal, locally
 * ✅ Executing the crosschain proposal to set a permission on the adminXchain
 *
 */
contract TestSetupE2EBase is LzTestHelper, IVoteContainer {
    using OptionsBuilder for bytes;
    using ProxyLib for address;
    using ProposalRefEncoder for uint256;
    using TallyMath for Tally;

    struct ChainBase {
        string chainName;
        // layer zero
        uint32 eid;
        uint256 chainid;
        address lzEndpoint;
        // OSX
        DAO dao;
        MockPluginSetupProcessor psp;
        MockDAOFactory daoFactory;
        // deployer
        address deployer;
        // we need admin to access the DAO
        AdminSetup adminSetup;
        Admin admin;
        PermissionLib.MultiTargetPermission[] adminUninstallPermissions;
    }

    struct VotingChain {
        ChainBase base;
        // contracts
        GovernanceERC20VotingChain token;
        ToucanRelay relay;
        ToucanVoting plugin;
        AdminXChain adminXChain;
        OFTTokenBridge bridge;
        // setups
        ToucanVotingSetup votingSetup;
        AdminXChainSetup adminXChainSetup;
        ToucanRelaySetup relaySetup;
        //permissions
        PermissionLib.MultiTargetPermission[] toucanRelayPermissions;
        PermissionLib.MultiTargetPermission[] adminXChainPermissions;
        // agents
        address voter;
    }

    struct ExecutionChain {
        ChainBase base;
        // contracts
        GovernanceERC20 token;
        GovernanceOFTAdapter adapter;
        ToucanReceiver receiver;
        ActionRelay actionRelay;
        ToucanVoting voting;
        // setups
        ToucanReceiverSetup receiverSetup;
        ToucanVotingSetup votingSetup;
        // permissions
        PermissionLib.MultiTargetPermission[] receiverPermissions;
        PermissionLib.MultiTargetPermission[] votingPermissions;
        // agents
        address voter;
    }

    function _deployOSX(ChainBase storage base) internal {
        // deploy the mock PSP with the admin plugin
        base.adminSetup = new AdminSetup();
        base.psp = new MockPluginSetupProcessor(address(base.adminSetup));
        base.daoFactory = new MockDAOFactory(base.psp);
    }

    function _deployDAOAndAdmin(ChainBase storage base) internal {
        // use the OSx DAO factory with the Admin Plugin
        bytes memory data = abi.encode(base.deployer);
        base.dao = base.daoFactory.createDao(_mockDAOSettings(), _mockPluginSettings(data));

        // nonce 0 is something?
        // nonce 1 is implementation contract
        // nonce 2 is the admin contract behind the proxy
        base.admin = Admin(computeAddress(address(base.adminSetup), 2));
        assertEq(base.admin.isMember(base.deployer), true, "trustedDeployer should be a member");
    }

    function _deployLayerZero(
        ChainBase storage executionChain,
        ChainBase storage votingChain
    ) internal {
        setUpEndpoints(2, LibraryType.UltraLightNode);

        executionChain.eid = 1;
        executionChain.lzEndpoint = endpoints[executionChain.eid];
        assertNotEq(executionChain.lzEndpoint, address(0), "execution endpoint should not be 0");

        votingChain.eid = 2;
        votingChain.lzEndpoint = endpoints[votingChain.eid];
        assertNotEq(votingChain.lzEndpoint, address(0), "voting endpoint should not be 0");
    }

    function _prepareUninstallAdmin(ChainBase storage base) internal {
        // psp will use the admin setup in next call
        base.psp.queueSetup(address(base.adminSetup));

        IPluginSetup.SetupPayload memory payload = IPluginSetup.SetupPayload({
            plugin: address(base.admin),
            currentHelpers: new address[](0),
            data: new bytes(0)
        });

        // prepare the uninstallation
        PermissionLib.MultiTargetPermission[] memory permissions = base.psp.prepareUninstallation(
            address(base.dao),
            _mockPrepareUninstallationParams(payload)
        );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < permissions.length; i++) {
            base.adminUninstallPermissions.push(permissions[i]);
        }
    }
}

contract TestSetupExecutionChainE2E is TestSetupE2EBase {
    function _prepareSetupToucanVoting(ExecutionChain storage chain) internal {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            new address[](1),
            new uint256[](1)
        );
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 0;

        GovernanceERC20 baseToken = new GovernanceERC20(
            IDAO(address(chain.base.dao)),
            "Test Token",
            "TT",
            mintSettings
        );

        chain.votingSetup = new ToucanVotingSetup(
            new ToucanVoting(),
            baseToken,
            new GovernanceWrappedERC20(
                IERC20Upgradeable(address(baseToken)),
                "Wrapped Test Token",
                "WTT"
            )
        );

        // push to the PSP
        chain.base.psp.queueSetup(address(chain.votingSetup));

        // prep the data
        IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
            votingMode: IToucanVoting.VotingMode.VoteReplacement,
            supportThreshold: 1e5,
            minParticipation: 1e5,
            minDuration: 1 days,
            minProposerVotingPower: 1 ether
        });

        ToucanVotingSetup.TokenSettings memory tokenSettings = ToucanVotingSetup.TokenSettings({
            addr: address(0),
            symbol: "TT",
            name: "TestToken"
        });

        mintSettings.receivers[0] = chain.voter;
        mintSettings.amounts[0] = 1_000_000 ether;

        bytes memory data = abi.encode(votingSettings, tokenSettings, mintSettings, false);

        (
            address votingPluginAddress,
            IPluginSetup.PreparedSetupData memory votingPluginPreparedSetupData
        ) = chain.base.psp.prepareInstallation(
                address(chain.base.dao),
                _mockPrepareInstallationParams(data)
            );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < votingPluginPreparedSetupData.permissions.length; i++) {
            chain.votingPermissions.push(votingPluginPreparedSetupData.permissions[i]);
        }

        chain.voting = ToucanVoting(votingPluginAddress);
        address[] memory helpers = votingPluginPreparedSetupData.helpers;
        chain.token = GovernanceERC20(helpers[0]);
    }

    function _prepareSetupReceiver(ExecutionChain storage chain) internal {
        // deploy receiver and set it as next address for PSP to use
        chain.receiverSetup = new ToucanReceiverSetup(
            new ToucanReceiver(),
            new GovernanceOFTAdapter(),
            new ActionRelay()
        );
        chain.base.psp.queueSetup(address(chain.receiverSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(chain.base.lzEndpoint), address(chain.voting));

        (
            address receiverPluginAddress,
            IPluginSetup.PreparedSetupData memory receiverPluginPreparedSetupData
        ) = chain.base.psp.prepareInstallation(
                address(chain.base.dao),
                _mockPrepareInstallationParams(data)
            );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < receiverPluginPreparedSetupData.permissions.length; i++) {
            chain.receiverPermissions.push(receiverPluginPreparedSetupData.permissions[i]);
        }

        chain.receiver = ToucanReceiver(payable(receiverPluginAddress));
        address[] memory helpers = receiverPluginPreparedSetupData.helpers;
        chain.adapter = GovernanceOFTAdapter(helpers[0]);
        chain.actionRelay = ActionRelay(helpers[1]);
    }

    function _applyInstallationsSetPeersRevokeAdmin(
        ExecutionChain storage chain,
        VotingChain storage votingChain
    ) internal {
        IDAO.Action[] memory actions = new IDAO.Action[](6);

        // action 0: apply the tokenVoting installation
        actions[0] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyInstallation,
                (
                    address(chain.base.dao),
                    _mockApplyInstallationParams(address(chain.voting), chain.votingPermissions)
                )
            )
        });

        // action 1: apply the receiver installation
        actions[1] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyInstallation,
                (
                    address(chain.base.dao),
                    _mockApplyInstallationParams(address(chain.receiver), chain.receiverPermissions)
                )
            )
        });

        // action 2,3,4: set the peers
        actions[2] = IDAO.Action({
            to: address(chain.receiver),
            value: 0,
            data: abi.encodeCall(
                chain.receiver.setPeer,
                (votingChain.base.eid, addressToBytes32(address(votingChain.relay)))
            )
        });

        actions[3] = IDAO.Action({
            to: address(chain.actionRelay),
            value: 0,
            data: abi.encodeCall(
                chain.actionRelay.setPeer,
                (votingChain.base.eid, addressToBytes32(address(votingChain.adminXChain)))
            )
        });

        actions[4] = IDAO.Action({
            to: address(chain.adapter),
            value: 0,
            data: abi.encodeCall(
                chain.adapter.setPeer,
                (votingChain.base.eid, addressToBytes32(address(votingChain.bridge)))
            )
        });

        // action 5: uninstall the admin plugin
        actions[5] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyUninstallation,
                (
                    address(chain.base.dao),
                    _mockApplyUninstallationParams(
                        address(chain.base.admin),
                        chain.base.adminUninstallPermissions
                    )
                )
            )
        });

        // wrap the actions in grant/revoke root permissions
        IDAO.Action[] memory wrappedActions = wrapGrantRevokeRoot(
            chain.base.dao,
            address(chain.base.psp),
            actions
        );

        // execute the actions
        vm.startPrank(chain.base.deployer);
        {
            chain.base.admin.executeProposal({
                _metadata: "",
                _actions: wrappedActions,
                _allowFailureMap: 0
            });
        }
        vm.stopPrank();
    }
}

contract TestSetupVotingChainE2E is TestSetupE2EBase {
    function _prepareSetupRelay(VotingChain storage chain) internal {
        // setup the voting chain: we need 2 setup contracts for the toucanRelay and the adminXChain
        chain.relaySetup = new ToucanRelaySetup(
            new ToucanRelay(),
            new OFTTokenBridge(),
            new GovernanceERC20VotingChain(IDAO(address(chain.base.dao)), "TestToken", "TT")
        );

        // set it on the mock psp
        chain.base.psp.queueSetup(address(chain.relaySetup));

        ToucanRelaySetup.InstallationParams memory params = ToucanRelaySetup.InstallationParams({
            lzEndpoint: address(chain.base.lzEndpoint),
            tokenName: "vTestToken",
            tokenSymbol: "vTT",
            dstEid: 1,
            votingBridgeBuffer: 20 minutes
        });

        // prepare the installation
        bytes memory data = abi.encode(params);
        (
            address toucanRelayAddress,
            IPluginSetup.PreparedSetupData memory toucanRelaySetupData
        ) = chain.base.psp.prepareInstallation(
                address(chain.base.dao),
                _mockPrepareInstallationParams(data)
            );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < toucanRelaySetupData.permissions.length; i++) {
            chain.toucanRelayPermissions.push(toucanRelaySetupData.permissions[i]);
        }

        chain.relay = ToucanRelay(toucanRelayAddress);
        address[] memory helpers = toucanRelaySetupData.helpers;
        chain.token = GovernanceERC20VotingChain(helpers[0]);
        chain.bridge = OFTTokenBridge(helpers[1]);
    }

    function _prepareSetupAdminXChain(VotingChain storage chain) internal {
        // setup the voting chain: we need 2 setup contracts for the toucanRelay and the adminXChain
        chain.adminXChainSetup = new AdminXChainSetup(new AdminXChain());

        // set it on the mock psp
        chain.base.psp.queueSetup(address(chain.adminXChainSetup));

        // prepare the installation
        bytes memory data = abi.encode(address(chain.base.lzEndpoint));
        (
            address adminXChainAddress,
            IPluginSetup.PreparedSetupData memory adminXChainSetupData
        ) = chain.base.psp.prepareInstallation(
                address(chain.base.dao),
                _mockPrepareInstallationParams(data)
            );

        // cannot write to storage from memory memory so just push here
        for (uint256 i = 0; i < adminXChainSetupData.permissions.length; i++) {
            chain.adminXChainPermissions.push(adminXChainSetupData.permissions[i]);
        }

        chain.adminXChain = AdminXChain(payable(adminXChainAddress));
    }

    function _applyInstallationsSetPeersRevokeAdmin(
        VotingChain storage chain,
        ExecutionChain storage executionChain
    ) internal {
        IDAO.Action[] memory actions = new IDAO.Action[](6);

        // action 0: apply the toucanRelay installation
        actions[0] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyInstallation,
                (
                    address(chain.base.dao),
                    _mockApplyInstallationParams(address(chain.relay), chain.toucanRelayPermissions)
                )
            )
        });

        // action 1: apply the adminXChain installation
        actions[1] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyInstallation,
                (
                    address(chain.base.dao),
                    _mockApplyInstallationParams(
                        address(chain.adminXChain),
                        chain.adminXChainPermissions
                    )
                )
            )
        });

        // action 2,3,4: set the peers
        actions[2] = IDAO.Action({
            to: address(chain.relay),
            value: 0,
            data: abi.encodeCall(
                chain.relay.setPeer,
                (executionChain.base.eid, addressToBytes32(address(executionChain.receiver)))
            )
        });

        actions[3] = IDAO.Action({
            to: address(chain.adminXChain),
            value: 0,
            data: abi.encodeCall(
                chain.adminXChain.setPeer,
                (executionChain.base.eid, addressToBytes32(address(executionChain.actionRelay)))
            )
        });

        actions[4] = IDAO.Action({
            to: address(chain.bridge),
            value: 0,
            data: abi.encodeCall(
                chain.adminXChain.setPeer,
                (executionChain.base.eid, addressToBytes32(address(executionChain.adapter)))
            )
        });

        // action 5: uninstall the admin plugin
        actions[5] = IDAO.Action({
            to: address(chain.base.psp),
            value: 0,
            data: abi.encodeCall(
                chain.base.psp.applyUninstallation,
                (
                    address(chain.base.dao),
                    _mockApplyUninstallationParams(
                        address(chain.base.admin),
                        chain.base.adminUninstallPermissions
                    )
                )
            )
        });

        // wrap the actions in grant/revoke root permissions
        IDAO.Action[] memory wrappedActions = wrapGrantRevokeRoot(
            chain.base.dao,
            address(chain.base.psp),
            actions
        );

        // execute the actions
        vm.startPrank(chain.base.deployer);
        {
            chain.base.admin.executeProposal({
                _metadata: "",
                _actions: wrappedActions,
                _allowFailureMap: 0
            });
        }
        vm.stopPrank();
    }
}

contract TestE2EFull is TestSetupExecutionChainE2E, TestSetupVotingChainE2E {
    using OptionsBuilder for bytes;

    ExecutionChain e;
    VotingChain v;

    address deployer = address(0x420);

    address eVoter = address(0x69);
    address vVoter0 = address(0x96);

    uint256 initialDeal = 1_000_000 ether;
    uint256 transferAmount = 100_000 ether;

    uint128 constant GAS_BRIDGE_TOKENS = 250_000;
    uint128 constant GAS_XCHAIN_PROPOSAL = 500_000;
    uint128 constant GAS_DISPATCH_VOTES = 500_000;

    uint proposalId;
    uint proposalRef;

    function setupExecutionChain() public {
        e.base.chainName = "Ethereum";
        e.base.chainid = 80085;
        e.base.deployer = deployer;
        e.voter = eVoter;

        _deployOSX(e.base);
        _deployDAOAndAdmin(e.base);
    }

    function setupVotingChain() public {
        v.base.chainName = "ZkSync";
        v.base.chainid = 1337;
        v.base.deployer = deployer;
        v.voter = vVoter0;

        _deployOSX(v.base);
        _deployDAOAndAdmin(v.base);
    }

    function setUp() public override {
        super.setUp();

        // reset clocks
        vm.warp(1);
        vm.roll(1);

        // initialize the chains
        setupExecutionChain();
        setupVotingChain();

        // deploy layerZero: this is cross chain
        _deployLayerZero(e.base, v.base);

        // setup the execution chain contracts
        _prepareSetupToucanVoting(e);
        _prepareSetupReceiver(e);
        _prepareUninstallAdmin(e.base);

        // setup the voting chain contracts
        _prepareSetupRelay(v);
        _prepareSetupAdminXChain(v);
        _prepareUninstallAdmin(v.base);

        // apply the installations and set the peers

        // exec chain
        _applyInstallationsSetPeersRevokeAdmin(e, v);

        // voting chain
        _applyInstallationsSetPeersRevokeAdmin(v, e);

        // give the agents cash money
        vm.deal(e.voter, initialDeal);
        vm.deal(v.voter, initialDeal);
        vm.deal(e.base.deployer, initialDeal);
        vm.deal(v.base.deployer, initialDeal);

        _addLabels();
    }

    function _addLabels() internal {
        vm.label(e.voter, "execution-chain-voter");
        vm.label(v.voter, "voting-chain-voter");

        vm.label(e.base.deployer, "execution-chain-deployer");
        vm.label(v.base.deployer, "voting-chain-deployer");

        vm.label(address(e.token), "execution-chain-token");
        vm.label(address(v.token), "voting-chain-token");

        vm.label(address(e.adapter), "execution-chain-adapter");
        vm.label(address(v.bridge), "voting-chain-bridge");

        vm.label(address(e.receiver), "execution-chain-receiver");
        vm.label(address(v.relay), "voting-chain-relay");

        vm.label(address(e.voting), "execution-chain-voting");

        vm.label(address(v.adminXChain), "voting-chain-admin");
        vm.label(address(e.actionRelay), "execution-chain-action-relay");
    }

    function testE2E() public {
        // first we want a user to bridge
        _bridgeTokens();
        // then we want to create a proposal
        _createProposal();
        // then do a vote
        // remote
        // bridge back
        _voteAndDispatch();

        // then execute the proposal, which will uninstall the xchain admin
        _executeBridgeProposal();

        // check the end state:
        // xchain admin should not have the permission
        assertFalse(
            v.base.dao.isGranted({
                _who: address(v.adminXChain),
                _where: address(v.base.dao),
                _permissionId: v.base.dao.EXECUTE_PERMISSION_ID(),
                _data: ""
            }),
            "xchainadmin should not have the permission"
        );
    }

    // bridge tokens from the execution chain to the voting chain
    function _bridgeTokens() internal {
        // the execution chain voter should have 1_000_000 toekens
        assertEq(e.token.balanceOf(e.voter), initialDeal);

        // transfer to the voting chain voter
        vm.startPrank(e.voter);
        {
            e.token.transfer(v.voter, transferAmount);
            assertEq(e.token.balanceOf(v.voter), transferAmount);
        }
        vm.stopPrank();

        // send the tokens to the voting chain
        vm.startPrank(v.voter);
        {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(
                GAS_BRIDGE_TOKENS,
                0
            );
            SendParam memory sendParams = SendParam({
                dstEid: v.base.eid,
                to: addressToBytes32(address(v.voter)),
                amountLD: transferAmount,
                minAmountLD: transferAmount,
                extraOptions: options,
                composeMsg: bytes(""),
                oftCmd: bytes("")
            });

            // fetch a quote
            MessagingFee memory msgFee = e.adapter.quoteSend(sendParams, false);
            assertEq(msgFee.lzTokenFee, 0, "lz fee should be 0");
            assertGt(msgFee.nativeFee, 0, "fee should be > 0");

            // send the message
            e.token.approve(address(e.adapter), transferAmount);
            e.adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
        }
        vm.stopPrank();

        // process the bridge transaction
        bridgeAdapterToOFTbridge();

        // check that the tokens were received
        assertEq(v.token.balanceOf(v.voter), transferAmount);
    }

    function _createProposal() internal {
        vm.roll(100);
        vm.warp(100);

        vm.startPrank(e.voter);
        {
            Tally memory votes = Tally(100_000, 200_000, 300_000);
            IDAO.Action[] memory actions = _createUninstallationProposal();

            proposalId = e.voting.createProposal({
                _metadata: "",
                _allowFailureMap: 0,
                _startDate: 0, // immediate
                _endDate: uint32(block.timestamp + 10 days),
                _tryEarlyExecution: false,
                _votes: votes,
                _actions: actions
            });
        }
        vm.stopPrank();

        // set the proposal ref
        proposalRef = e.receiver.getProposalRef(proposalId);
    }

    // note that the clocks are synced automatically
    function _voteAndDispatch() internal {
        // warp it forward 1 second to allow voting
        vm.warp(block.timestamp + 1);

        vm.startPrank(v.voter);
        {
            v.relay.vote(proposalRef, Tally(0, transferAmount, 0));

            // get a xchain quote
            ToucanRelay.LzSendParams memory quote = v.relay.quote(proposalRef, GAS_DISPATCH_VOTES);

            // dispatch it
            v.relay.dispatchVotes{value: quote.fee.nativeFee}(proposalRef, quote);
        }
        vm.stopPrank();

        // process the message
        bridgeRelayToReceiver();
    }

    function _executeBridgeProposal() internal {
        // ff to end of the proposal
        vm.warp(block.timestamp + 10 days);

        // execute the proposal
        vm.startPrank(e.voter);
        {
            // send the dao some cash to pay for the xchain fees
            (bool success, ) = address(payable(e.base.dao)).call{value: 10 ether}("");
            assertTrue(success, "should have sent the DAO some cash");

            e.voting.execute(proposalId);
        }
        vm.stopPrank();

        // process the message
        bridgeActionRelayToAdminXChain();
    }

    function bridgeAdapterToOFTbridge() internal {
        verifyPackets(v.base.eid, address(v.bridge));
    }

    function bridgeOFTBridgeToAdapter() internal {
        verifyPackets(e.base.eid, address(e.adapter));
    }

    function bridgeRelayToReceiver() internal {
        verifyPackets(e.base.eid, address(e.receiver));
    }

    function bridgeActionRelayToAdminXChain() internal {
        verifyPackets(v.base.eid, address(v.adminXChain));
    }

    function _createUninstallationProposal() public view returns (IDAO.Action[] memory) {
        IDAO.Action[] memory innerActions = new IDAO.Action[](1);

        // these are executed on the voting chain
        innerActions[0] = IDAO.Action({
            to: address(v.base.dao),
            data: abi.encodeCall(
                v.base.dao.revoke,
                (
                    /* where */ address(v.base.dao),
                    /* who */ address(v.adminXChain),
                    /* permissionId */ v.base.dao.EXECUTE_PERMISSION_ID()
                )
            ),
            value: 0
        });

        // fetch a quote for all this
        ActionRelay.LzSendParams memory params = e.actionRelay.quote(
            e.voting.proposalCount(), // proposal id that will be created
            innerActions,
            0, // allowFailureMap
            v.base.eid,
            GAS_XCHAIN_PROPOSAL
        );

        // now we can create the execute action
        IDAO.Action[] memory actions = new IDAO.Action[](1);

        // the action on this chain will be to send to the action relay
        // the cross chain request
        actions[0] = IDAO.Action({
            to: address(e.actionRelay),
            data: abi.encodeCall(
                e.actionRelay.relayActions,
                (
                    e.voting.proposalCount(),
                    innerActions,
                    0, // allowFailureMap
                    params
                )
            ),
            // this is super important, it's not a zero value
            // transfer because the layer zero endpoint will
            // expect a fee from the DAO
            value: params.fee.nativeFee
        });

        return actions;
    }
}
