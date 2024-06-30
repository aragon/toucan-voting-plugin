// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IOFT} from "@lz-oft/interfaces/IOFT.sol";
import {IOAppCore, ILayerZeroEndpointV2} from "@lz-oapp/interfaces/IOAppCore.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {ProxyLib} from "@libs/ProxyLib.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";

/// @title ToucanRelaySetup
/// @author Aragon X
/// @notice The setup contract of the `ToucanRelay` plugin.
/// @custom:security-contact sirt@aragon.org
contract ToucanRelaySetup is PluginSetup {
    using ProxyLib for address;

    /// @notice Thrown if the token name or symbol is empty.
    error InvalidTokenNameOrSymbol();

    /// @notice Thrown if the helpers length is incorrect.
    error IncorrectHelpersLength(uint8 expected, uint8 actual);

    /// @notice The ID of the permission required to call admin functions on the bridge and the relay.
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR");

    /// @notice address of the token bridge implementation.
    address public immutable bridgeBase;

    /// @notice address of the voting token implementation.
    address public immutable votingTokenBase;

    /// @notice address of the relay implementation.
    address public immutable relayBase;

    /// @notice Sets the implementation contracts for the `ToucanRelay` plugin and helpers.
    /// @param _relayBase The address of the `ToucanRelay` implementation contract.
    /// @param _bridgeBase The address of the `OFTTokenBridge` implementation contract.
    /// @param _votingTokenBase The address of the `GovernanceERC20VotingChain` implementation contract.
    constructor(
        ToucanRelay _relayBase,
        OFTTokenBridge _bridgeBase,
        GovernanceERC20VotingChain _votingTokenBase
    ) PluginSetup() {
        relayBase = address(_relayBase);
        bridgeBase = address(_bridgeBase);
        votingTokenBase = address(_votingTokenBase);
    }

    /// @return The address of the relay implementation.
    function implementation() external view returns (address) {
        return relayBase;
    }

    /// @inheritdoc IPluginSetup
    /// @dev The DAO should call 'setPeer' on the OApps during the applyInstall phase,
    /// once the execution chain addresses are known.
    /// TODO: should we deploy the AdminXChain here or seperately?
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // decode the data
        (address lzEndpoint, string memory tokenName, string memory tokenSymbol) = abi.decode(
            _data,
            (address, string, string)
        );

        // check the token name and symbol are not empty
        if (isEmpty(tokenName) || isEmpty(tokenSymbol)) revert InvalidTokenNameOrSymbol();

        // deploy the voting token, bridge and relay
        address token = votingTokenBase.deployUUPSProxy(
            abi.encodeCall(
                GovernanceERC20VotingChain.initialize,
                (IDAO(_dao), tokenName, tokenSymbol)
            )
        );

        address bridge = bridgeBase.deployUUPSProxy(
            abi.encodeCall(OFTTokenBridge.initialize, (token, lzEndpoint, _dao))
        );

        // plugin = relayBase.deployUUPSProxy(
        //     abi.encodeCall(ToucanRelay.initialize, (token, lzEndpoint, _dao))
        // );

        // setup permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // bridge can mint and burn tokens
        // may be redundant but avoids conditionals
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            permissionId: GovernanceERC20VotingChain(token).MINT_PERMISSION_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: bridge,
            where: token
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            permissionId: GovernanceERC20VotingChain(token).BURN_PERMISSION_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: bridge,
            where: token
        });

        // dao is the oapp administrator for the bridge and the relay
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            permissionId: OAPP_ADMINISTRATOR_ID,
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: bridge
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            permissionId: OAPP_ADMINISTRATOR_ID,
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: plugin
        });

        // set the return data
        address[] memory helpers = new address[](2);
        helpers[0] = token;
        helpers[1] = bridge;

        preparedSetupData.permissions = permissions;
        preparedSetupData.helpers = helpers;
    }

    function isEmpty(string memory _str) internal pure returns (bool) {
        return keccak256(abi.encode(_str)) == keccak256(abi.encode(""));
    }

    /// @notice Deploys the Voting chain token - a timestamp based ERC0Votes token.
    /// @param _dao The DAO address on this chain.
    /// @param _name The name of the token on this chain.
    /// @param _symbol The symbol of the token on this chain.
    function deployToken(
        address _dao,
        string memory _name,
        string memory _symbol
    ) public returns (address) {}

    /// @inheritdoc IPluginSetup
    /// @dev The relay will be uninstalled but we keep the bridge setup as-is.
    /// Strictly speaking, there's nothing to uninstall on the DAO but we revoke the permissions nonetheless.
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external pure returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // fetch the bridge address
        address[] memory currentHelpers = _payload.currentHelpers;
        if (currentHelpers.length != 2) {
            revert IncorrectHelpersLength(2, uint8(currentHelpers.length));
        }
        address bridge = currentHelpers[1];

        permissions = new PermissionLib.MultiTargetPermission[](2);

        // remove OAPP administrator ids from relay and bridge
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: OAPP_ADMINISTRATOR_ID
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: bridge,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: OAPP_ADMINISTRATOR_ID
        });
    }
}
