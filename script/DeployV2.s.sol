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

// script utils
import {Script} from "forge-std/Script.sol";
import {ISetup, SetupE2EBase, SetupExecutionChainE2E, SetupVotingChainE2E} from "src/e2e/E2ESetup.sol";

// one off
import {createTestDAO} from "@mocks/MockDAO.sol";

// deploy the toucan voting script on arbitrum sepolia
contract DeployToucanVotin is Script {
    ToucanVotingSetup setup;
    DAO dao;

    address deployer;

    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
    uint256 mint = 1_000_000_000 ether;

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        GovernanceERC20 token = deployToken();
        setup = new ToucanVotingSetup(
            new ToucanVoting(),
            token,
            new GovernanceWrappedERC20(IERC20Upgradeable(address(token)), "test", "test")
        );

        dao = createTestDAO(deployer);

        bytes memory data = baseSetupData(address(0));

        (, IPluginSetup.PreparedSetupData memory preparedData) = setup.prepareInstallation(
            address(dao),
            data
        );

        dao.applyMultiTargetPermissions(preparedData.permissions);
    }

    function deployToken() internal returns (GovernanceERC20) {
        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings(
            new address[](1),
            new uint256[](1)
        );
        mintSettings.receivers[0] = address(this);
        mintSettings.amounts[0] = 0;

        GovernanceERC20 baseToken = new GovernanceERC20(
            IDAO(address(dao)),
            "Test Token",
            "TT",
            mintSettings
        );
        return baseToken;
    }

    function baseSetupData(address _token) public view returns (bytes memory) {
        // prep the data
        IToucanVoting.VotingSettings memory votingSettings = IToucanVoting.VotingSettings({
            votingMode: IToucanVoting.VotingMode.VoteReplacement,
            supportThreshold: 1e5,
            minParticipation: 1e5,
            minDuration: 1 days,
            minProposerVotingPower: 1 ether
        });

        ToucanVotingSetup.TokenSettings memory tokenSettings = ToucanVotingSetup.TokenSettings({
            addr: _token,
            symbol: "TT",
            name: "TestToken"
        });

        GovernanceERC20.MintSettings memory mintSettings = GovernanceERC20.MintSettings({
            receivers: new address[](2),
            amounts: new uint256[](2)
        });
        mintSettings.receivers[0] = JUAR;
        mintSettings.amounts[0] = mint;
        mintSettings.receivers[1] = ME;
        mintSettings.amounts[1] = mint;

        bytes memory data = abi.encode(votingSettings, tokenSettings, mintSettings, false);
        return data;
    }
}

/// @notice Registry contract for deployment addresses that can be fetched later.
contract ToucanDeployRegistry is ISetup {
    address public deployer;

    struct Deployment {
        VotingChain votingChain;
        ExecutionChain executionChain;
    }

    event WroteExecutionChain(uint256 id);
    event WroteVotingChain(uint256 id);

    mapping(uint256 => Deployment) public deployments;

    constructor() {
        deployer = msg.sender;
    }

    function writeExecutionChain(uint256 id, ExecutionChain memory executionChain) public {
        require(msg.sender == deployer, "DeployRegistry: only deployer can write");

        // write minimal values needed for xchain
        deployments[id].executionChain.base.eid = executionChain.base.eid;

        // actionRelay, adapter, receiver
        deployments[id].executionChain.actionRelay = executionChain.actionRelay;
        deployments[id].executionChain.adapter = executionChain.adapter;
        deployments[id].executionChain.receiver = executionChain.receiver;

        if (address(executionChain.base.dao) != address(0)) {
            // Copy ExecutionChain base values
            deployments[id].executionChain.base.chainName = executionChain.base.chainName;
            deployments[id].executionChain.base.eid = executionChain.base.eid;
            deployments[id].executionChain.base.chainid = executionChain.base.chainid;
            deployments[id].executionChain.base.lzEndpoint = executionChain.base.lzEndpoint;
            deployments[id].executionChain.base.dao = executionChain.base.dao;
            deployments[id].executionChain.base.psp = executionChain.base.psp;
            deployments[id].executionChain.base.daoFactory = executionChain.base.daoFactory;
            deployments[id].executionChain.base.deployer = executionChain.base.deployer;
            deployments[id].executionChain.base.adminSetup = executionChain.base.adminSetup;
            deployments[id].executionChain.base.admin = executionChain.base.admin;
            deployments[id].executionChain.base.adminUninstallPermissions = executionChain
                .base
                .adminUninstallPermissions;

            // Copy ExecutionChain specific values
            deployments[id].executionChain.token = executionChain.token;
            deployments[id].executionChain.adapter = executionChain.adapter;
            deployments[id].executionChain.receiver = executionChain.receiver;
            deployments[id].executionChain.actionRelay = executionChain.actionRelay;
            deployments[id].executionChain.voting = executionChain.voting;
            deployments[id].executionChain.receiverSetup = executionChain.receiverSetup;
            deployments[id].executionChain.votingSetup = executionChain.votingSetup;
            deployments[id].executionChain.receiverPermissions = executionChain.receiverPermissions;
            deployments[id].executionChain.votingPermissions = executionChain.votingPermissions;
            deployments[id].executionChain.voter = executionChain.voter;
        }

        emit WroteExecutionChain(id);
    }

    function writeVotingChain(uint256 id, VotingChain memory votingChain) public {
        require(msg.sender == deployer, "DeployRegistry: only deployer can write");

        // write minimal values needed for xchain
        deployments[id].votingChain.base.eid = votingChain.base.eid;
        deployments[id].votingChain.adminXChain = votingChain.adminXChain;
        deployments[id].votingChain.bridge = votingChain.bridge;
        deployments[id].votingChain.relay = votingChain.relay;

        // write the rest of the values if we have them
        if (address(votingChain.base.dao) != address(0)) {
            // Copy VotingChain base values
            deployments[id].votingChain.base.chainName = votingChain.base.chainName;
            deployments[id].votingChain.base.chainid = votingChain.base.chainid;
            deployments[id].votingChain.base.lzEndpoint = votingChain.base.lzEndpoint;
            deployments[id].votingChain.base.dao = votingChain.base.dao;
            deployments[id].votingChain.base.psp = votingChain.base.psp;
            deployments[id].votingChain.base.daoFactory = votingChain.base.daoFactory;
            deployments[id].votingChain.base.deployer = votingChain.base.deployer;
            deployments[id].votingChain.base.adminSetup = votingChain.base.adminSetup;
            deployments[id].votingChain.base.admin = votingChain.base.admin;
            deployments[id].votingChain.base.adminUninstallPermissions = votingChain
                .base
                .adminUninstallPermissions;

            // Copy VotingChain specific values
            deployments[id].votingChain.token = votingChain.token;
            deployments[id].votingChain.adminXChainSetup = votingChain.adminXChainSetup;
            deployments[id].votingChain.relaySetup = votingChain.relaySetup;
            deployments[id].votingChain.toucanRelayPermissions = votingChain.toucanRelayPermissions;
            deployments[id].votingChain.adminXChainPermissions = votingChain.adminXChainPermissions;
            deployments[id].votingChain.voter = votingChain.voter;
        }

        emit WroteVotingChain(id);
    }
}

contract DeployE2E is Script, SetupExecutionChainE2E, SetupVotingChainE2E {
    using OptionsBuilder for bytes;

    ExecutionChain e;
    VotingChain v;

    address deployer;

    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
    uint256 mint = 1_000_000_000 ether;

    uint256 DEPLOYMENT_ID = 1;

    ToucanDeployRegistry registryArbitrum;
    ToucanDeployRegistry registryOptimism;

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function _executionChain() internal view returns (bool) {
        string memory result = vm.envString("EXECUTION_OR_VOTING");
        if (keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked("EXECUTION"))) {
            return true;
        } else if (keccak256(abi.encodePacked(result)) == keccak256(abi.encodePacked("VOTING"))) {
            return false;
        } else {
            revert(
                "Invalid env variable EXECUTION_OR_VOTING, must be either 'EXECUTION' or 'VOTING'"
            );
        }
    }

    function run() public broadcast {
        bool isExecutionChain = _executionChain();

        if (isExecutionChain) {
            console2.log("Running Execution Chain");

            if (address(registryArbitrum) == address(0)) {
                console2.log("REGISTRY NOT FOUND, creating new one");
                registryArbitrum = new ToucanDeployRegistry();
                console2.log("REGISTRY: %s", address(registryArbitrum));
            }

            setupExecutionChain();
            stage1ExecutionChain();
        } else {
            console2.log("Running Voting Chain");

            if (address(registryOptimism) == address(0)) {
                console2.log("REGISTRY NOT FOUND, creating new one");
                registryOptimism = new ToucanDeployRegistry();
                console2.log("REGISTRY: %s", address(registryOptimism));
            }

            setupVotingChain();
            stage1VotingChain();
        }
    }

    // run these before everything on execution chain
    function setupExecutionChain() public {
        e.base.chainName = "ArbitrumSepolia";
        e.base.chainid = 40231;
        e.base.deployer = deployer;
        e.base.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        e.voter = deployer;
    }

    // run these before everything on voting chain
    function setupVotingChain() public {
        v.base.chainName = "OptimismSepolia";
        v.base.chainid = 40232;
        v.base.deployer = deployer;
        v.base.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        v.voter = deployer;
    }

    // deploy all the contracts on execution chain
    function stage1ExecutionChain() public {
        _deployOSX(e.base);
        _deployDAOAndAdmin(e.base);
        _prepareSetupToucanVoting(e);
        _prepareSetupReceiver(e);
        _prepareUninstallAdmin(e.base);

        registryArbitrum.writeExecutionChain(DEPLOYMENT_ID, e);
    }

    // deploy all the contracts on voting chain
    function stage1VotingChain() public {
        _deployOSX(v.base);
        _deployDAOAndAdmin(v.base);
        _prepareSetupRelay(v);
        _prepareSetupAdminXChain(v);
        _prepareUninstallAdmin(v.base);

        registryOptimism.writeVotingChain(DEPLOYMENT_ID, v);
    }

    function stage2ExecutionChain() public {
        (VotingChain memory vc, ExecutionChain memory ec) = registryArbitrum.deployments(
            DEPLOYMENT_ID
        );
        _checkRequiredData(vc);

        _applyInstallationsSetPeersRevokeAdmin(ec, vc);
    }

    function stage2VotingChain() public {
        (VotingChain memory vc, ExecutionChain memory ec) = registryOptimism.deployments(
            DEPLOYMENT_ID
        );
        _checkRequiredData(ec);
        _applyInstallationsSetPeersRevokeAdmin(vc, ec);
    }

    /// TODO: running these requires having the contract addresses
    function _checkRequiredData(VotingChain memory votingChain) internal view {
        require(votingChain.base.eid > 0, "VotingChain: missing EID");
        // relay, adminXchain and bridge
        require(address(votingChain.relay) != address(0), "VotingChain: missing relay");
        require(address(votingChain.adminXChain) != address(0), "VotingChain: missing adminXChain");
        require(address(votingChain.bridge) != address(0), "VotingChain: missing bridge");
    }

    function _checkRequiredData(ExecutionChain storage executionChain) internal view {
        require(executionChain.base.eid > 0, "ExecutionChain: missing EID");
        // receiver, voting, adapter
        require(address(executionChain.receiver) != address(0), "ExecutionChain: missing receiver");
        require(
            address(executionChain.actionRelay) != address(0),
            "ExecutionChain: missing actionRelay"
        );
        require(address(executionChain.adapter) != address(0), "ExecutionChain: missing adapter");
    }

    // apply installation on the execution chain
    function _applyInstallationsSetPeersRevokeAdmin(
        ExecutionChain storage chain,
        VotingChain storage votingChain
    ) internal {
        IDAO.Action[] memory actions = _executionActions(chain, votingChain);

        chain.base.admin.executeProposal({_metadata: "", _actions: actions, _allowFailureMap: 0});
    }

    // apply installation on the voting chain
    function _applyInstallationsSetPeersRevokeAdmin(
        VotingChain storage chain,
        ExecutionChain storage executionChain
    ) internal {
        IDAO.Action[] memory actions = _votingActions(chain, executionChain);

        chain.base.admin.executeProposal({_metadata: "", _actions: actions, _allowFailureMap: 0});
    }
}
