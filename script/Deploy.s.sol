// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {Script, console2} from "forge-std/Script.sol";
import {Vm} from "forge-std/Vm.sol";

// external contracts
import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {SendParam, OFTLimit, OFTFeeDetail, OFTReceipt, MessagingFee} from "@lz-oft/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {TokenVoting as ToucanVoting} from "@aragon/token-voting/TokenVoting.sol";
import {ITokenVoting, IVoteContainer} from "@aragon/token-voting/ITokenVoting.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// external test utils
import "forge-std/console2.sol";

// internal contracts
import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ProposalIdCodec} from "@libs/ProposalIdCodec.sol";

// internal test utils
import "@utils/converters.sol";
import "@utils/deployers.sol";
import "forge-std/console2.sol";

import {MockDAOSimplePermission as MockDAO} from "test/mocks/MockDAO.sol";
import {AragonTest} from "test/base/AragonTest.sol";

contract DeployToucan is Script {
    struct LzChain {
        uint32 eid;
        address endpoint;
    }

    address deployer;
    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;

    LzChain SEPOLIA = LzChain(40161, 0x6EDCE65403992e310A62460808c4b910D972f10f);
    LzChain ARBITRUM_SEPOLIA = LzChain(40231, 0x6EDCE65403992e310A62460808c4b910D972f10f);

    using OptionsBuilder for bytes;
    using ProxyLib for address;
    using ProposalIdCodec for uint256;

    // execution chain
    uint32 EID_EXECUTION_CHAIN = SEPOLIA.eid;
    // uint256  EVM_EXECUTION_CHAIN = 137;

    address daoExecutionChain;
    GovernanceERC20 tokenExecutionChain;
    GovernanceOFTAdapter adapter;
    OFTTokenBridge bridge;
    ToucanReceiver receiver;
    address layerZeroEndpointExecutionChain = SEPOLIA.endpoint;

    // voting chain
    uint32 EID_VOTING_CHAIN = ARBITRUM_SEPOLIA.eid;

    address daoVotingChain;
    GovernanceERC20VotingChain tokenVotingChain;
    ToucanRelay relay;
    ToucanVoting plugin;
    address layerZeroEndpointVotingChain = ARBITRUM_SEPOLIA.endpoint;

    // agents
    address executionVoter = ME;
    address votingVoter = JUAR;
    // cash they get in governance tokens
    uint constant INITIAL_MINT = 10_000 ether;

    // voting params
    uint32 constant SUPPORT_THRESHOLD = 1;
    uint32 constant MIN_PARTICIPATION = 1;
    uint64 constant MIN_DURATION = 3600;
    uint constant MIN_PROPOSER_VOTING_POWER = 1;
    ToucanVoting.VotingMode constant MODE = ITokenVoting.VotingMode.VoteReplacement;

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
        if (_executionChain()) {
            console2.log("Running Execution Chain");
            runExecutionChain();
            _connectOApps_executionChain();
        } else {
            console2.log("Running Voting Chain");
            runVotingChain();
            _connectOApps_votingChain();
        }
    }

    function runVotingChain() public {
        _deployVotingChain();

        console2.log("Contracts deployed:");

        console2.log("Voting Chain:");
        console2.log("Bridge: ", address(bridge));
        console2.log("Relay: ", address(relay));
        console2.log("DAO: ", daoVotingChain);
        console2.log("Token: ", address(tokenVotingChain));
    }

    function runExecutionChain() public {
        _deployExecutionChain();

        console2.log("Contracts deployed:");

        console2.log("Execution Chain:");
        console2.log("DAO: ", daoExecutionChain);
        console2.log("Token: ", address(tokenExecutionChain));
        console2.log("Adapter: ", address(adapter));
        console2.log("Receiver: ", address(receiver));
        console2.log("Plugin: ", address(plugin));
    }

    function _deployPlugin(
        ToucanVoting.VotingSettings memory settings
    ) internal returns (ToucanVoting) {
        // deploy implementation
        address base = address(new ToucanVoting());
        // encode the initalizer
        bytes memory data = abi.encodeCall(
            ToucanVoting.initialize,
            (IDAO(daoExecutionChain), settings, IVotesUpgradeable(tokenExecutionChain))
        );
        // deploy and return the proxy
        address deployed = base.deployUUPSProxy(data);

        return ToucanVoting(deployed);
    }

    function _mintSettings(
        uint _qty
    ) internal view returns (GovernanceERC20.MintSettings memory settings) {
        address[] memory receivers = new address[](2);
        uint256[] memory amounts = new uint256[](2);

        receivers[0] = executionVoter;
        amounts[0] = _qty;

        receivers[1] = votingVoter;
        amounts[1] = _qty;

        settings = GovernanceERC20.MintSettings(receivers, amounts);
        return settings;
    }

    function createMockDAO() public returns (DAO) {
        return _createMockDAO(address(this));
    }

    function _deployExecutionChain() internal {
        // setup the dao
        daoExecutionChain = address(_createMockDAO(deployer));

        // setup the token
        tokenExecutionChain = new GovernanceERC20(
            IDAO(daoExecutionChain),
            "Execution Token",
            "EXT",
            _mintSettings(INITIAL_MINT)
        );

        // initalize the adapter, receiver and plugin
        ToucanVoting.VotingSettings memory settings = ITokenVoting.VotingSettings({
            votingMode: MODE,
            supportThreshold: SUPPORT_THRESHOLD,
            minParticipation: MIN_PARTICIPATION,
            minDuration: MIN_DURATION,
            minProposerVotingPower: MIN_PROPOSER_VOTING_POWER
        });

        plugin = _deployPlugin(settings);

        receiver = deployToucanReceiver({
            _governanceToken: address(tokenExecutionChain),
            _lzEndpoint: layerZeroEndpointExecutionChain,
            _dao: daoExecutionChain,
            _votingPlugin: address(plugin)
        });

        adapter = deployGovernanceOFTAdapter({
            _token: address(tokenExecutionChain),
            _voteProxy: address(receiver),
            _lzEndpoint: layerZeroEndpointExecutionChain,
            _dao: daoExecutionChain
        });

        // configure the OApps
        adapter.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(bridge)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }

    function _deployVotingChain() internal {
        daoVotingChain = address(_createMockDAO(deployer));

        // setup the token
        tokenVotingChain = new GovernanceERC20VotingChain({
            _dao: IDAO(daoVotingChain),
            _name: "Voting Token",
            _symbol: "VOT"
        });

        // initalize the bridge and relay
        relay = deployToucanRelay(
            address(tokenVotingChain),
            layerZeroEndpointVotingChain,
            daoVotingChain
        );

        bridge = deployTokenBridge({
            _token: address(tokenVotingChain),
            _lzEndpoint: layerZeroEndpointVotingChain,
            _dao: daoVotingChain
        });

        // we need to allow the bridge to mint and burn tokens
        // todo - these should be done in the setup contracts.
        DAO(payable(daoVotingChain)).grant({
            _where: address(tokenVotingChain),
            _who: address(bridge),
            _permissionId: tokenVotingChain.MINT_PERMISSION_ID()
        });

        DAO(payable(daoVotingChain)).grant({
            _where: address(tokenVotingChain),
            _who: address(bridge),
            _permissionId: tokenVotingChain.BURN_PERMISSION_ID()
        });

        // configure the OApps
        bridge.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(adapter)));
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
    }

    function _createMockDAO(address _initalOwner) internal returns (DAO) {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        string memory _daoURI = "ipfs://";
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: _initalOwner,
            _trustedForwarder: address(0),
            daoURI_: _daoURI
        });

        _dao.grant({
            _who: address(_dao),
            _where: address(_dao),
            _permissionId: _dao.ROOT_PERMISSION_ID()
        });

        return _dao;
    }

    function _connectOApps_executionChain() internal {
        // the oftadapter and the bridge have a bidrectional relationship
        adapter.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(bridge)));
        receiver.setPeer(EID_VOTING_CHAIN, addressToBytes32(address(relay)));
    }

    function _connectOApps_votingChain() internal {
        bridge.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(adapter)));
        relay.setPeer(EID_EXECUTION_CHAIN, addressToBytes32(address(receiver)));
    }

    function _connectOApps() internal {
        if (_executionChain()) {
            _connectOApps_executionChain();
        } else {
            _connectOApps_votingChain();
        }
    }

    function getProposalTally(
        uint256 _proposalId
    ) internal view returns (IVoteContainer.Tally memory tally) {
        (, , , tally, , ) = plugin.getProposal(_proposalId);
    }
}
