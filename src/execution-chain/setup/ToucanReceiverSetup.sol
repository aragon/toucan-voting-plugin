// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";

import {IGovernanceWrappedERC20} from "@interfaces/IGovernanceWrappedERC20.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {IProposal} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/IProposal.sol";

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {PluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginSetup.sol";

import {GovernanceOFTAdapter} from "../crosschain/GovernanceOFTAdapter.sol";
import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";
import {GovernanceWrappedERC20} from "@aragon/token-voting/ERC20/governance/GovernanceWrappedERC20.sol";
import {TokenVoting as ToucanVoting} from "@aragon/token-voting/TokenVoting.sol";

import {ToucanReceiver} from "../crosschain/ToucanReceiver.sol";
import {deployToucanReceiver} from "@utils/deployers.sol";

/// @title ToucanReceiverSetup
/// @author Aragon X - 2022-2023
/// @notice The setup contract of the `ToucanReceiver` plugin.
/// @custom:security-contact sirt@aragon.org
/// TODO: this is a WIP until we have 1967 proxies setup for the receiver
contract ToucanReceiverSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    /// @dev TODO: Migrate this constant to a common library that can be shared across plugins.
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The address of the `ToucanReceiver` base contract.
    // solhint-disable-next-line immutable-vars-naming
    ToucanReceiver private immutable receiverBase;

    // solhint-disable-next-line immutable-vars-naming
    address public immutable oftAdapterBase;

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the plugin implementation contract
    constructor(
        GovernanceOFTAdapter _adapterBase
    ) PluginSetup(address(0 /*  will be replaced with new ToucanReceiver() */)) {
        receiverBase = ToucanReceiver(IMPLEMENTATION);
        oftAdapterBase = address(_adapterBase);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `ToucanReceiver` plugin,
        // and the required helpers
        (address adapter, address token, address lzEndpoint, address votingPlugin) = abi.decode(
            _data,
            (address, address, address, address)
        );

        if (token == address(0)) {
            revert("cant have empty token");
        }

        if (votingPlugin == address(0)) {
            revert("cant have empty voting plugin");
        }

        if (lzEndpoint == address(0)) {
            revert("cant have empty lz endpoint");
        }

        // Prepare and deploy plugin proxy.
        plugin = address(
            deployToucanReceiver({
                _governanceToken: token,
                _lzEndpoint: lzEndpoint,
                _dao: _dao,
                _votingPlugin: votingPlugin
            })
        );
        bool adapterAddressNotZero = adapter != address(0);
        address[] memory helpers = new address[](1);

        if (adapterAddressNotZero) {
            // Prepare helpers.
            // TODO in theory this should be a clone but needs work to make
            // it initializable
            adapter = address(
                new GovernanceOFTAdapter({
                    _token: token,
                    _voteProxy: plugin,
                    _lzEndpoint: lzEndpoint,
                    _dao: _dao
                })
            );
        }

        helpers[0] = adapter;

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](
                adapterAddressNotZero ? 3 : 4
            );

        // Set plugin permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: receiverBase.RECEIVER_ADMIN_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: receiverBase.SWEEP_COLLECTOR_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        if (!adapterAddressNotZero) {
            bytes32 setDelegatePermission = GovernanceOFTAdapter(token)
                .SET_CROSSCHAIN_DELEGATE_ID();

            permissions[3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: setDelegatePermission
            });
        }

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        permissions = new PermissionLib.MultiTargetPermission[](3);

        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: receiverBase.RECEIVER_ADMIN_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: receiverBase.SWEEP_COLLECTOR_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });
    }
}
