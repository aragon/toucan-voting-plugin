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
import {ToucanReceiver, ToucanReceiverSetup, GovernanceOFTAdapter, ActionRelay} from "@execution-chain/setup/ToucanReceiverSetup.sol";

/// voting chain
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {ToucanRelay, ToucanRelaySetup, OFTTokenBridge} from "@voting-chain/setup/ToucanRelaySetup.sol";
import {AdminXChain, AdminXChainSetup} from "@voting-chain/setup/AdminXChainSetup.sol";

// test utils
import {MockPluginSetupProcessor} from "@mocks/osx/MockPSP.sol";
import {MockDAOFactory, PluginSetupRef} from "@mocks/osx/MockDAOFactory.sol";
import "@helpers/OSxHelpers.sol";
import "forge-std/console2.sol";

// script utils
import {Script} from "forge-std/Script.sol";
import {ISetup, SetupE2EBase, SetupExecutionChainE2E, SetupVotingChainE2E} from "src/e2e/E2ESetup.sol";
import {ToucanDeployRegistry} from "src/e2e/Registry.sol";

contract DeployE2E is Script, SetupExecutionChainE2E, SetupVotingChainE2E {
    using OptionsBuilder for bytes;

    // deployer will receive the tokens on execution chain
    address deployer;

    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
    uint256 mint = 1_000_000_000 ether;

    // increment this each deployment: not great solution but fine for now
    uint256 DEPLOYMENT_ID = 3;

    // these should be singletons per network
    ToucanDeployRegistry registryArbitrum =
        ToucanDeployRegistry(0xfA8Df779f6bCC0aEc166F3DAa608B0674224e6cf);
    ToucanDeployRegistry registryOptimism =
        ToucanDeployRegistry(0x9a16A85f40E74A225370c5F604feEdaD86ed7e71);

    // CONTRACTS NEEDED
    // Voting Chain
    address TOUCAN_RELAY = 0x65991B62B5067c1B4941E6F6A97add0e45280a3A;
    address payable ADMIN_XCHAIN = payable(0xaA256bCaF9ef49A26f4F5DE5A8aBf7095EA11617);
    address BRIDGE = 0x7B0913Bb7D4B4C174A03baBD9172fa96Fe52C279;

    // Execution Chain
    address payable RECEIVER = payable(0xA52bEC62C3CA39d999778D671B5024CB7ef7E0a0);
    address ACTION_RELAY = 0xF4B9Fc72B402a822AC6bbA7845349bB4f62D8e19;
    address ADAPTER = 0xF104E7C74a3350e73B02A55375bABbE5a70a1447;

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    modifier requiresRegistry(bool isOnExecutionChain) {
        if (isOnExecutionChain) {
            require(address(registryArbitrum) != address(0), "Registry not found");
        } else {
            require(address(registryOptimism) != address(0), "Registry not found");
        }
        _;
    }

    function setupExecutionChain() public view returns (ExecutionChain memory e) {
        e.base.chainName = "ArbitrumSepolia";
        e.base.eid = 40231;
        e.base.deployer = deployer;
        e.base.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        e.voter = deployer;
    }

    function setupVotingChain() public view returns (VotingChain memory v) {
        v.base.chainName = "OptimismSepolia";
        v.base.eid = 40232;
        v.base.deployer = deployer;
        v.base.lzEndpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
        v.voter = deployer;
    }

    function _isOnExecutionChain() internal view returns (bool) {
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
        // set env vars
        uint stage = vm.envUint("STAGE");
        bool isOnExecutionChain = _isOnExecutionChain();

        // enter the switch for each chain
        if (isOnExecutionChain) {
            console2.log("Running Execution Chain");
            executionChain(stage);
        } else {
            console2.log("Running Voting Chain");
            votingChain(stage);
        }
    }

    function executionChain(uint256 stage) public {
        if (stage == 0) {
            deployRegistryExecutionChain();
        } else if (stage == 1) {
            ExecutionChain memory e = setupExecutionChain();
            initExecutionChain(e);
        } else if (stage == 2) {
            logAddressesForVotingChainExecutionChain();
        } else if (stage == 3) {
            setRequiredXChainContractAddressesExecutionChain(
                DEPLOYMENT_ID,
                TOUCAN_RELAY,
                ADMIN_XCHAIN,
                BRIDGE
            );
            applyPermissionsExecutionChain();
        } else if (stage == 4) {
            logRegistryExecution();
        } else {
            revert("Invalid stage");
        }
    }

    function votingChain(uint256 stage) public {
        if (stage == 0) {
            deployRegistryVotingChain();
        } else if (stage == 1) {
            VotingChain memory v = setupVotingChain();
            initVotingChain(v);
        } else if (stage == 2) {
            logAddressesForExecutionChainVotingchain();
        } else if (stage == 3) {
            setRequiredXChainContractAddressesVotingChain(
                DEPLOYMENT_ID,
                RECEIVER,
                ACTION_RELAY,
                ADAPTER
            );
            applyPermissionsVotingChain();
        } else if (stage == 4) {
            logRegistryVoting();
        } else {
            revert("Invalid stage");
        }
    }

    function deployRegistryExecutionChain() public {
        if (address(registryArbitrum) == address(0)) {
            console2.log("REGISTRY NOT FOUND, creating new one");
            registryArbitrum = new ToucanDeployRegistry();
            console2.log("REGISTRY: %s", address(registryArbitrum));
        } else {
            console2.log("REGISTRY FOUND: %s", address(registryArbitrum));
        }
    }

    function deployRegistryVotingChain() public {
        if (address(registryOptimism) == address(0)) {
            console2.log("REGISTRY NOT FOUND, creating new one");
            registryOptimism = new ToucanDeployRegistry();
            console2.log("REGISTRY: %s", address(registryOptimism));
        } else {
            console2.log("REGISTRY FOUND: %s", address(registryOptimism));
        }
    }

    function initExecutionChain(ExecutionChain memory e) public requiresRegistry(true) {
        if (address(registryArbitrum) == address(0)) {
            console2.log("REGISTRY NOT FOUND, creating new one");
            registryArbitrum = new ToucanDeployRegistry();
            console2.log("REGISTRY: %s", address(registryArbitrum));
        }

        _deployOSX(e.base);
        _deployDAOAndAdmin(e.base);
        _prepareSetupToucanVoting(e);
        _prepareSetupReceiver(e);
        _prepareUninstallAdmin(e.base);

        registryArbitrum.writeExecutionChain(DEPLOYMENT_ID, e);
    }

    function initVotingChain(VotingChain memory v) public requiresRegistry(false) {
        if (address(registryOptimism) == address(0)) {
            console2.log("REGISTRY NOT FOUND, creating new one");
            registryOptimism = new ToucanDeployRegistry();
            console2.log("REGISTRY: %s", address(registryOptimism));
        }

        // grab the basic execution chain
        ExecutionChain memory ec = setupExecutionChain();

        _deployOSX(v.base);
        _deployDAOAndAdmin(v.base);
        _prepareSetupRelay(v, ec);
        _prepareSetupAdminXChain(v);
        _prepareUninstallAdmin(v.base);

        registryOptimism.writeVotingChain(DEPLOYMENT_ID, v);
    }

    function logAddressesForVotingChainExecutionChain() public view requiresRegistry(true) {
        (, ExecutionChain memory ec) = registryArbitrum.deployments(DEPLOYMENT_ID);

        console2.log("Receiver: %s", address(ec.receiver));
        console2.log("ActionRelay: %s", address(ec.actionRelay));
        console2.log("Adapter: %s", address(ec.adapter));
    }

    function logAddressesForExecutionChainVotingchain() public view requiresRegistry(false) {
        (VotingChain memory vc, ) = registryOptimism.deployments(DEPLOYMENT_ID);

        console2.log("Relay: %s", address(vc.relay));
        console2.log("AdminXChain: %s", address(vc.adminXChain));
        console2.log("Bridge: %s", address(vc.bridge));
    }

    // stage 2a: set the required contract addresses FROM the voting chain
    // on the execution chain registry
    function setRequiredXChainContractAddressesExecutionChain(
        uint256 id,
        address relay,
        address payable adminXChain,
        address bridge
    ) public requiresRegistry(true) {
        require(relay != address(0), "Relay address is required");
        require(adminXChain != address(0), "AdminXChain address is required");
        require(bridge != address(0), "Bridge address is required");

        VotingChain memory vc = setupVotingChain();
        vc.relay = ToucanRelay(relay);
        vc.adminXChain = AdminXChain(adminXChain);
        vc.bridge = OFTTokenBridge(bridge);

        registryArbitrum.writeVotingChain(id, vc);
    }

    // stage 2b: set the required contract addresses FROM the execution chain
    // on the voting chain registry
    function setRequiredXChainContractAddressesVotingChain(
        uint256 id,
        address payable receiver,
        address actionRelay,
        address adapter
    ) public requiresRegistry(false) {
        require(receiver != address(0), "Receiver address is required");
        require(actionRelay != address(0), "ActionRelay address is required");
        require(adapter != address(0), "Adapter address is required");

        ExecutionChain memory ec = setupExecutionChain();
        ec.receiver = ToucanReceiver(receiver);
        ec.actionRelay = ActionRelay(actionRelay);
        ec.adapter = GovernanceOFTAdapter(adapter);

        registryOptimism.writeExecutionChain(id, ec);
    }

    /// Stage 3a, with all the required contract addresses set, we can now
    /// connect peers and revoke admin
    function applyPermissionsExecutionChain() public requiresRegistry(true) {
        (VotingChain memory vc, ExecutionChain memory ec) = registryArbitrum.deployments(
            DEPLOYMENT_ID
        );
        _checkRequiredData(vc);

        _applyInstallationsSetPeersRevokeAdmin(ec, vc);
    }

    /// Stage 3b, with all the required contract addresses set, we can now
    /// connect peers and revoke admin
    function applyPermissionsVotingChain() public requiresRegistry(false) {
        (VotingChain memory vc, ExecutionChain memory ec) = registryOptimism.deployments(
            DEPLOYMENT_ID
        );
        _checkRequiredData(ec);
        _applyInstallationsSetPeersRevokeAdmin(vc, ec);
    }

    function _checkRequiredData(VotingChain memory v) internal pure {
        require(v.base.eid > 0, "VotingChain: missing EID");
        // relay, adminXchain and bridge
        require(address(v.relay) != address(0), "VotingChain: missing relay");
        require(address(v.adminXChain) != address(0), "VotingChain: missing adminXChain");
        require(address(v.bridge) != address(0), "VotingChain: missing bridge");
    }

    function _checkRequiredData(ExecutionChain memory e) internal pure {
        require(e.base.eid > 0, "ExecutionChain: missing EID");
        // receiver, voting, adapter
        require(address(e.receiver) != address(0), "ExecutionChain: missing receiver");
        require(address(e.actionRelay) != address(0), "ExecutionChain: missing actionRelay");
        require(address(e.adapter) != address(0), "ExecutionChain: missing adapter");
    }

    // apply installation on the execution chain
    function _applyInstallationsSetPeersRevokeAdmin(
        ExecutionChain memory e,
        VotingChain memory v
    ) internal {
        IDAO.Action[] memory actions = _executionActions(e, v);

        e.base.admin.executeProposal({_metadata: "", _actions: actions, _allowFailureMap: 0});
    }

    // apply installation on the voting chain
    function _applyInstallationsSetPeersRevokeAdmin(
        VotingChain memory v,
        ExecutionChain memory e
    ) internal {
        IDAO.Action[] memory actions = _votingActions(v, e);

        v.base.admin.executeProposal({_metadata: "", _actions: actions, _allowFailureMap: 0});
    }

    function logRegistryExecution() public view requiresRegistry(true) {
        (VotingChain memory v, ExecutionChain memory e) = registryArbitrum.deployments(
            DEPLOYMENT_ID
        );

        console2.log("ExecutionChain:");
        console2.log("  chainName: %s", e.base.chainName);
        console2.log("  eid: %s", e.base.eid);
        console2.log("  lzEndpoint: %s", e.base.lzEndpoint);
        console2.log("  deployer: %s", e.base.deployer);

        console2.log("DAO and Contracts");
        console2.log("  dao: %s", address(e.base.dao));
        console2.log("  toucanVoting: %s", address(e.voting));
        console2.log("  receiver: %s", address(e.receiver));
        console2.log("  actionRelay: %s", address(e.actionRelay));
        console2.log("  adapter: %s", address(e.adapter));
        console2.log("  token: %s", address(e.token));

        console2.log("VotingChain Data:");
        console2.log("  chainName: %s", v.base.chainName);
        console2.log("  eid: %s", v.base.eid);
        console2.log("  relay: %s", address(v.relay));
        console2.log("  adminXChain: %s", address(v.adminXChain));
        console2.log("  bridge: %s", address(v.bridge));
    }

    function logRegistryVoting() public view requiresRegistry(false) {
        (VotingChain memory v, ExecutionChain memory e) = registryOptimism.deployments(
            DEPLOYMENT_ID
        );

        console2.log("VotingChain:");
        console2.log("  chainName: %s", v.base.chainName);
        console2.log("  eid: %s", v.base.eid);
        console2.log("  lzEndpoint: %s", v.base.lzEndpoint);
        console2.log("  deployer: %s", v.base.deployer);

        console2.log("DAO and Contracts");
        console2.log("  dao: %s", address(v.base.dao));
        console2.log("  relay: %s", address(v.relay));
        console2.log("  adminXChain: %s", address(v.adminXChain));
        console2.log("  bridge: %s", address(v.bridge));
        console2.log("  token: %s", address(v.token));

        console2.log("ExecutionChain Data:");
        console2.log("  chainName: %s", e.base.chainName);
        console2.log("  eid: %s", e.base.eid);
        console2.log("  receiver: %s", address(e.receiver));
    }
}
