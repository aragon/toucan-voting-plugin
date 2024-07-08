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

contract BridgeAndSend is Script, ISetup {
    using OptionsBuilder for bytes;

    address deployer;

    address constant JUAR = 0x8bF1e340055c7dE62F11229A149d3A1918de3d74;
    address constant ME = 0x7771c1510509C0dA515BDD12a57dbDd8C58E5363;
    address constant ALSO_ME = 0x35DFF23Cf68ad92021Ebe1FE043De6b77435E5e9;
    uint256 mint = 1_000_000_000 ether;

    uint256 DEPLOYMENT_ID = 3;

    ToucanDeployRegistry registryArbitrum =
        ToucanDeployRegistry(0xfA8Df779f6bCC0aEc166F3DAa608B0674224e6cf);
    ToucanDeployRegistry registryOptimism =
        ToucanDeployRegistry(0x9a16A85f40E74A225370c5F604feEdaD86ed7e71);

    uint32 EID_VOTING_CHAIN = 40232;

    modifier broadcast() {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployer);
        _;
        vm.stopBroadcast();
    }

    function run() public broadcast {
        if (DEPLOYMENT_ID == 0) revert("DEPLOYMENT_ID not set");
        // get the contracts
        (, ExecutionChain memory e) = registryArbitrum.deployments(DEPLOYMENT_ID);

        // bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(250000, 0);
        // SendParam memory sendParams = SendParam({
        //     dstEid: EID_VOTING_CHAIN,
        //     to: addressToBytes32(address(ME)),
        //     amountLD: 10_000 ether,
        //     minAmountLD: 10_000 ether,
        //     extraOptions: options,
        //     composeMsg: bytes(""),
        //     oftCmd: bytes("")
        // });

        // // fetch a quote
        // MessagingFee memory msgFee = e.adapter.quoteSend(sendParams, false);

        // // send the message
        // e.token.approve(address(e.adapter), 10_000 ether);
        // e.adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));

        // // send to carlos as well
        // sendParams.to = addressToBytes32(address(JUAR));
        // msgFee = e.adapter.quoteSend(sendParams, false);
        // e.token.approve(address(e.adapter), 10_000 ether);
        // e.adapter.send{value: msgFee.nativeFee}(sendParams, msgFee, address(this));
        e.token.transfer(address(ALSO_ME), 10_000 ether);
    }
}
