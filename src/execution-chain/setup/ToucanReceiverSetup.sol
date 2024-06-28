// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {IProposal} from "@aragon/osx/core/plugin/proposal/IProposal.sol";
import {IGovernanceWrappedERC20} from "@interfaces/IGovernanceWrappedERC20.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";
import {ToucanVoting as ToucanVoting, IToucanVoting as IToucanVoting} from "@toucan-voting/ToucanVoting.sol";

import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";
import {ActionRelay} from "@execution-chain/crosschain/ActionRelay.sol";

/// @title ToucanReceiverSetup
/// @author Aragon X - 2024
/// @notice The setup contract of the `ToucanReceiver` plugin.
/// @custom:security-contact sirt@aragon.org
contract ToucanReceiverSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The identifier of the `OAPP_ADMINISTRATOR` permission.
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR");

    /// @notice The interface ID of the `IToucanVoting` interface.
    bytes4 public constant TOKEN_VOTING_INTERFACE_ID = 0x2366d905;

    /// @notice The base contract of the `ToucanReceiver` plugin from which to create proxies.
    address public immutable toucanReceiverBase;

    /// @notice The base contract of the `GovernanceOFTAdapter` helper from which to create proxies.
    address public immutable oftAdapterBase;

    /// @notice The base contract of the `ActionRelay` helper from which to create proxies.
    address public immutable actionRelayBase;

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice Thrown if the voting plugin does not support the `IToucanVoting` interface.
    error InvalidInterface();

    /// @notice Thrown if the voting plugin is not in vote replacement mode.
    error NotInVoteReplacementMode();

    /// @notice Deploys the setup by binding the implementation contracts required during installation.
    constructor(
        ToucanReceiver _toucanReceiverBase,
        GovernanceOFTAdapter _adapterBase,
        ActionRelay _actionRelayBase
    ) PluginSetup() {
        toucanReceiverBase = address(_toucanReceiverBase);
        oftAdapterBase = address(_adapterBase);
        actionRelayBase = address(_actionRelayBase);
    }

    /// @return The address of the `ToucanReceiver` implementation contract.
    function implementation() external view returns (address) {
        return toucanReceiverBase;
    }

    /// @inheritdoc IPluginSetup
    /// @dev The DAO should call `setPeer` on the XChain contracts while applying the installation.
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        (address lzEndpoint, address _votingPlugin) = abi.decode(_data, (address, address));

        // check the voting plugin and fetch the associated token
        ToucanVoting votingPlugin = validateVotingPlugin(_votingPlugin);
        address token = address(votingPlugin.getVotingToken());

        // deploy our plugin, adapter and action relay
        plugin = toucanReceiverBase.deployUUPSProxy(
            abi.encodeCall(ToucanReceiver.initialize, (token, lzEndpoint, _dao, _votingPlugin))
        );

        address adapter = oftAdapterBase.deployUUPSProxy(
            abi.encodeCall(GovernanceOFTAdapter.initialize, (token, plugin, lzEndpoint, _dao))
        );

        address actionRelay = actionRelayBase.deployUUPSProxy(
            abi.encodeCall(ActionRelay.initialize, (lzEndpoint, _dao))
        );

        // encode our setup data with permissions and helpers
        PermissionLib.MultiTargetPermission[] memory permissions = getPermissions(
            _dao,
            payable(plugin),
            adapter,
            actionRelay,
            PermissionLib.Operation.Grant
        );

        address[] memory helpers = new address[](2);
        helpers[0] = adapter;
        helpers[1] = actionRelay;

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @notice Validates the voting plugin by checking if it supports the `IToucanVoting` interface
    /// and is in vote replacement mode.
    /// @param _votingPlugin The address of the voting plugin to validate.
    /// @return The `ToucanVoting` instance of the voting plugin, if it is valid, else reverts.
    function validateVotingPlugin(
        address _votingPlugin
    ) public view virtual returns (ToucanVoting) {
        ToucanVoting votingPlugin = ToucanVoting(_votingPlugin);

        if (!votingPlugin.supportsInterface(TOKEN_VOTING_INTERFACE_ID)) {
            revert InvalidInterface();
        }

        if (!(uint(votingPlugin.votingMode()) == uint(IToucanVoting.VotingMode.VoteReplacement))) {
            revert NotInVoteReplacementMode();
        }

        return votingPlugin;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // check the helpers length
        if (_payload.currentHelpers.length != 2) {
            revert WrongHelpersArrayLength(_payload.currentHelpers.length);
        }

        address adapter = _payload.currentHelpers[0];
        address actionRelay = _payload.currentHelpers[1];

        permissions = getPermissions(
            _dao,
            payable(_payload.plugin),
            adapter,
            actionRelay,
            PermissionLib.Operation.Revoke
        );
    }

    /// @notice Returns the permissions required for the plugin install and uninstall.
    /// @param _dao The DAO address on this chain.
    /// @param _plugin The plugin proxy address.
    /// @param _adapter The address of the GovernanceOFTAdapter helper.
    /// @param _actionRelay The address of the ActionRelay helper.
    /// @param _grantOrRevoke The operation to perform.
    function getPermissions(
        address _dao,
        address payable _plugin,
        address _adapter,
        address _actionRelay,
        PermissionLib.Operation _grantOrRevoke
    ) public view returns (PermissionLib.MultiTargetPermission[] memory) {
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](5);

        // Set the permissions for the plugin
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            permissionId: OAPP_ADMINISTRATOR_ID,
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: _plugin
        });

        // Set the permissions for the adapter
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            permissionId: OAPP_ADMINISTRATOR_ID,
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: _adapter
        });

        // Set the permissions for the action relay
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            permissionId: OAPP_ADMINISTRATOR_ID,
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: _actionRelay
        });

        // Set the XChain action relayer permission for the action relay
        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            permissionId: ActionRelay(_actionRelay).XCHAIN_ACTION_RELAYER_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: _actionRelay
        });

        // Set the sweep collector permission for the plugin
        permissions[4] = PermissionLib.MultiTargetPermission({
            operation: _grantOrRevoke,
            permissionId: ToucanReceiver(_plugin).SWEEP_COLLECTOR_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: _plugin
        });

        return permissions;
    }
}
