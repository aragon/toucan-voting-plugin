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
import {ILayerZeroEndpointV2, IMessageLibManager} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {IMessageLib, SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLib.sol";
import {ExecutorConfig, UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/uln302/SendUln302.sol";

// aragon contracts
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {PermissionManager} from "@aragon/osx/core/permission/PermissionManager.sol";
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

// give an EOA admin rights on the DAO
contract SetOAppConf is Script, ISetup, IVoteContainer {
    using OptionsBuilder for bytes;

    address deployer;

    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
    address constant ALSO_ME = 0x35DFF23Cf68ad92021Ebe1FE043De6b77435E5e9;
    uint256 mint = 1_000_000_000 ether;

    uint256 DEPLOYMENT_ID = 2; // arb - zksync

    // Arbitrum mainnet
    ToucanDeployRegistry registryExec =
        ToucanDeployRegistry(0x9a16A85f40E74A225370c5F604feEdaD86ed7e71);

    // don't use these with live clients but for tests it's okay
    uint64 constant CONFIRMATIONS = 1;
    uint8 constant REQUIREDDVNCOUNT = 1;
    uint8 constant OPTIONALDVNCOUNT = 0;
    uint8 constant OPTIONALDVNTHRESHOLD = 0;
    uint32 constant MAXMESSAGESIZE = type(uint32).max;

    struct OAppConfChain {
        address executor;
        address l0dvn;
        uint32 eid;
        address sendLib;
        address receiveLib;
    }

    // this is the non defaults
    struct OAppConfXChain {
        OAppConfChain e; // executionchain
        OAppConfChain v; // votingchain
    }

    // default executor config
    function executorConfig(
        OAppConfChain memory srcChain,
        OAppConfChain memory dstChain
    ) public pure returns (SetConfigParam memory) {
        return
            SetConfigParam({
                eid: dstChain.eid,
                configType: 1, // Executor Config
                config: abi.encode(ExecutorConfig(MAXMESSAGESIZE, srcChain.executor))
            });
    }

    // default uln config
    function ulnConfig(
        OAppConfChain memory srcChain,
        OAppConfChain memory dstChain
    ) public pure returns (SetConfigParam memory) {
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = srcChain.l0dvn;
        return
            SetConfigParam({
                eid: dstChain.eid,
                configType: 2, // ULN Config
                config: abi.encode(
                    UlnConfig(
                        CONFIRMATIONS,
                        REQUIREDDVNCOUNT,
                        OPTIONALDVNCOUNT,
                        OPTIONALDVNTHRESHOLD,
                        requiredDVNs,
                        new address[](0) // optionalDVNs
                    )
                )
            });
    }

    function setConfigParams(
        OAppConfChain memory srcChain,
        OAppConfChain memory dstChain
    ) public pure returns (SetConfigParam[] memory) {
        SetConfigParam[] memory config = new SetConfigParam[](2);
        config[0] = ulnConfig(srcChain, dstChain);
        config[1] = executorConfig(srcChain, dstChain);
        return config;
    }

    function setSendLibAction(
        address lzEndpoint,
        address oapp,
        uint32 eid,
        address sendLib
    ) public pure returns (IDAO.Action memory) {
        return
            IDAO.Action({
                to: lzEndpoint,
                data: abi.encodeCall(IMessageLibManager.setSendLibrary, (oapp, eid, sendLib)),
                value: 0
            });
    }

    function setSendConfigAction(
        address lzEndpoint,
        address oapp,
        address sendLib,
        SetConfigParam[] memory config
    ) public pure returns (IDAO.Action memory) {
        return
            IDAO.Action({
                to: lzEndpoint,
                data: abi.encodeCall(IMessageLibManager.setConfig, (oapp, sendLib, config)),
                value: 0
            });
    }

    function setReceiveLibAction(
        address lzEndpoint,
        address oapp,
        uint32 eid,
        address receiveLib
    ) public pure returns (IDAO.Action memory) {
        return
            IDAO.Action({
                to: lzEndpoint,
                data: abi.encodeCall(
                    IMessageLibManager.setReceiveLibrary,
                    (oapp, eid, receiveLib, 0)
                ),
                value: 0
            });
    }

    function setReceiveConfigAction(
        address lzEndpoint,
        address oapp,
        address receiveLib,
        SetConfigParam[] memory config
    ) public pure returns (IDAO.Action memory) {
        // we only need the uln config
        SetConfigParam[] memory ulnConf = new SetConfigParam[](1);
        ulnConf[0] = config[0];
        return
            IDAO.Action({
                to: lzEndpoint,
                data: abi.encodeCall(IMessageLibManager.setConfig, (oapp, receiveLib, ulnConf)),
                value: 0
            });
    }

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        (, ExecutionChain memory e) = registryExec.deployments(DEPLOYMENT_ID);

        address srcOApp = address(e.adapter);

        OAppConfChain memory arbitrum = OAppConfChain({
            sendLib: 0x975bcD720be66659e3EB3C0e4F1866a3020E493A,
            eid: 30110,
            executor: 0x31CAe3B7fB82d847621859fb1585353c5720660D,
            l0dvn: 0x2f55C492897526677C5B68fb199ea31E2c126416,
            receiveLib: 0x7B9E184e07a6EE1aC23eAe0fe8D6Be2f663f05e6
        });

        OAppConfChain memory zkSync = OAppConfChain({
            sendLib: 0x07fD0e370B49919cA8dA0CE842B8177263c0E12c,
            eid: 30165,
            executor: 0x664e390e672A811c12091db8426cBb7d68D5D8A6,
            l0dvn: 0x620A9DF73D2F1015eA75aea1067227F9013f5C51,
            receiveLib: 0x04830f6deCF08Dec9eD6C3fCAD215245B78A59e1
        });
        SetConfigParam[] memory config = setConfigParams(arbitrum, zkSync);

        // actions are:
        // 1. set the send library for all the sender oapps
        // 2. set the config for all the sender oapps
        // 3. set the receive library for all the receiver oapps
        // 4. set the config for all the receiver oapps
        IDAO.Action[] memory actions = new IDAO.Action[](6);

        // adapter - send and receive
        // these were already called but if you were doing from scratch you would do this
        // actions[0] = setSendLibAction(
        //     e.base.lzEndpoint,
        //     address(e.adapter),
        //     zkSync.eid,
        //     arbitrum.sendLib
        // );
        // actions[1] = setSendConfigAction(address(e.adapter), arbitrum.sendLib, config);

        actions[0] = setReceiveLibAction(
            e.base.lzEndpoint,
            address(e.adapter),
            zkSync.eid,
            arbitrum.receiveLib
        );
        actions[1] = setReceiveConfigAction(
            e.base.lzEndpoint,
            address(e.adapter),
            arbitrum.receiveLib,
            config
        );

        // receiver - receive only
        actions[2] = setReceiveLibAction(
            e.base.lzEndpoint,
            address(e.receiver),
            zkSync.eid,
            arbitrum.receiveLib
        );
        actions[3] = setReceiveConfigAction(
            e.base.lzEndpoint,
            address(e.receiver),
            arbitrum.receiveLib,
            config
        );

        // action relay - send only
        actions[4] = setSendLibAction(
            e.base.lzEndpoint,
            address(e.actionRelay),
            zkSync.eid,
            arbitrum.sendLib
        );
        actions[5] = setSendConfigAction(
            e.base.lzEndpoint,
            address(e.actionRelay),
            arbitrum.sendLib,
            config
        );

        // ping it through the multisig
        e.base.multisig.createProposal({
            _metadata: "Set OApp Conf",
            _actions: actions,
            _allowFailureMap: 0,
            _startDate: 0, // now
            _endDate: uint32(block.timestamp + 1 hours),
            _tryExecution: true,
            _approveProposal: true
        });
    }
}
