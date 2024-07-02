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
import {ToucanDeployRegistry} from "src/e2e/Registry.sol";

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

            // loop through permissions to set them
            for (uint256 i = 0; i < executionChain.base.adminUninstallPermissions.length; i++) {
                deployments[id].executionChain.base.adminUninstallPermissions.push(
                    executionChain.base.adminUninstallPermissions[i]
                );
            }

            // Copy ExecutionChain specific values
            deployments[id].executionChain.token = executionChain.token;
            deployments[id].executionChain.adapter = executionChain.adapter;
            deployments[id].executionChain.receiver = executionChain.receiver;
            deployments[id].executionChain.actionRelay = executionChain.actionRelay;
            deployments[id].executionChain.voting = executionChain.voting;
            deployments[id].executionChain.receiverSetup = executionChain.receiverSetup;
            deployments[id].executionChain.votingSetup = executionChain.votingSetup;
            deployments[id].executionChain.voter = executionChain.voter;

            // loop through permissions to set them
            for (uint256 i = 0; i < executionChain.receiverPermissions.length; i++) {
                deployments[id].executionChain.receiverPermissions.push(
                    executionChain.receiverPermissions[i]
                );
            }

            for (uint256 i = 0; i < executionChain.votingPermissions.length; i++) {
                deployments[id].executionChain.votingPermissions.push(
                    executionChain.votingPermissions[i]
                );
            }
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

            // loop through permissions to set them
            for (uint256 i = 0; i < votingChain.base.adminUninstallPermissions.length; i++) {
                deployments[id].votingChain.base.adminUninstallPermissions.push(
                    votingChain.base.adminUninstallPermissions[i]
                );
            }

            // Copy VotingChain specific values
            deployments[id].votingChain.token = votingChain.token;
            deployments[id].votingChain.adminXChainSetup = votingChain.adminXChainSetup;
            deployments[id].votingChain.relaySetup = votingChain.relaySetup;
            deployments[id].votingChain.voter = votingChain.voter;

            // loop through permissions to set them
            for (uint256 i = 0; i < votingChain.toucanRelayPermissions.length; i++) {
                deployments[id].votingChain.toucanRelayPermissions.push(
                    votingChain.toucanRelayPermissions[i]
                );
            }

            for (uint256 i = 0; i < votingChain.adminXChainPermissions.length; i++) {
                deployments[id].votingChain.adminXChainPermissions.push(
                    votingChain.adminXChainPermissions[i]
                );
            }
        }

        emit WroteVotingChain(id);
    }
}
