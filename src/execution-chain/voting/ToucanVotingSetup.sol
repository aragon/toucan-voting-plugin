// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {GovernanceERC20} from "./ERC20/governance/GovernanceERC20.sol";
import {IGovernanceWrappedERC20} from "./ERC20/governance/IGovernanceWrappedERC20.sol";
import {GovernanceWrappedERC20} from "./ERC20/governance/GovernanceWrappedERC20.sol";

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {PermissionLib} from "@aragon/osx/core/permission/PermissionLib.sol";
import {IPluginSetup} from "@aragon/osx/framework/plugin/setup/IPluginSetup.sol";
import {PluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import {ToucanVoting} from "./ToucanVoting.sol";
import {IToucanVoting} from "./IToucanVoting.sol";

import {ProxyLib} from "@libs/ProxyLib.sol";

// import "hardhat/console.sol";

/// @title ToucanVotingSetup
/// @author Aragon X - 2022-2023
/// @notice The setup contract of the `ToucanVoting` plugin.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract ToucanVotingSetup is PluginSetup {
    using Address for address;
    using Clones for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
    /// @dev TODO: Migrate this constant to a common library that can be shared across plugins.
    bytes32 public constant EXECUTE_PERMISSION_ID = keccak256("EXECUTE_PERMISSION");

    /// @notice The address of the `ToucanVoting` base contract.
    // solhint-disable-next-line immutable-vars-naming
    ToucanVoting private immutable tokenVotingBase;

    /// @notice The address of the `GovernanceERC20` base contract.
    // solhint-disable-next-line immutable-vars-naming
    address public immutable governanceERC20Base;

    /// @notice The address of the `GovernanceWrappedERC20` base contract.
    // solhint-disable-next-line immutable-vars-naming
    address public immutable governanceWrappedERC20Base;

    /// @notice The token settings struct.
    /// @param addr The token address. If this is `address(0)`, a new `GovernanceERC20` token is deployed.
    /// If not, the existing token is wrapped as an `GovernanceWrappedERC20`.
    /// @param name The token name. This parameter is only relevant if the token address is `address(0)`.
    /// @param symbol The token symbol. This parameter is only relevant if the token address is `address(0)`.
    struct TokenSettings {
        address addr;
        string name;
        string symbol;
    }

    /// @notice Thrown if token address is passed which is not a token.
    /// @param token The token address
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
    /// @param token The token address
    error TokenNotERC20(address token);

    /// @notice Thrown if passed helpers array is of wrong length.
    /// @param length The array length of passed helpers.
    error WrongHelpersArrayLength(uint256 length);

    /// @notice The contract constructor deploying the plugin implementation contract
    /// and receiving the governance token base contracts to proxy from.
    /// @param _tokenVotingBase The base `ToucanVoting` contract to create proxies from.
    /// @param _governanceERC20Base The base `GovernanceERC20` contract to create proxies from.
    /// @param _governanceWrappedERC20Base The base `GovernanceWrappedERC20` contract to create proxies from.
    constructor(
        ToucanVoting _tokenVotingBase,
        GovernanceERC20 _governanceERC20Base,
        GovernanceWrappedERC20 _governanceWrappedERC20Base
    ) PluginSetup() {
        tokenVotingBase = _tokenVotingBase;
        governanceERC20Base = address(_governanceERC20Base);
        governanceWrappedERC20Base = address(_governanceWrappedERC20Base);
    }

    function implementation() external view returns (address) {
        return address(tokenVotingBase);
    }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // Decode `_data` to extract the params needed for deploying and initializing `ToucanVoting` plugin,
        // and the required helpers
        (
            IToucanVoting.VotingSettings memory votingSettings,
            TokenSettings memory tokenSettings,
            // only used for GovernanceERC20(token is not passed)
            GovernanceERC20.MintSettings memory mintSettings,
            bool bypassTokenValidation
        ) = abi.decode(
                _data,
                (IToucanVoting.VotingSettings, TokenSettings, GovernanceERC20.MintSettings, bool)
            );

        address token = tokenSettings.addr;
        bool tokenAddressNotZero = token != address(0);
        bool deployedAragonToken = false;

        // Prepare helpers.
        address[] memory helpers = new address[](1);

        if (bypassTokenValidation) {
            // do noting, essentially GOTO setting helpers
        } else if (tokenAddressNotZero) {
            if (!token.isContract()) {
                revert TokenNotContract(token);
            }

            if (!_isERC20(token)) {
                revert TokenNotERC20(token);
            }

            if (missingInterface(token)) {
                token = governanceWrappedERC20Base.clone();
                // User already has a token. We need to wrap it in
                // GovernanceWrappedERC20 in order to make the token
                // include governance functionality.
                GovernanceWrappedERC20(token).initialize(
                    IERC20Upgradeable(tokenSettings.addr),
                    tokenSettings.name,
                    tokenSettings.symbol
                );
                deployedAragonToken = true;
            }
        } else {
            // Clone a `GovernanceERC20`.
            token = governanceERC20Base.clone();
            GovernanceERC20(token).initialize(
                IDAO(_dao),
                tokenSettings.name,
                tokenSettings.symbol,
                mintSettings
            );
            deployedAragonToken = true;
        }

        helpers[0] = token;

        // Prepare and deploy plugin proxy.
        plugin = address(tokenVotingBase).deployUUPSProxy(
            abi.encodeCall(ToucanVoting.initialize, (IDAO(_dao), votingSettings, token))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](
                tokenAddressNotZero ? 2 : 3
            );

        // Set plugin permissions to be granted.
        // Grant the list of permissions of the plugin to the DAO.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        // Grant `EXECUTE_PERMISSION` of the DAO to the plugin.
        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: _dao,
            who: plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });

        // If the token was our Governance ERC20, grant mint permission to the DAO.
        // if we didn't deploy an aragon token, we can't guarantee mint permission will exist on the token.
        if (deployedAragonToken) {
            permissions[2] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: GovernanceERC20(token).MINT_PERMISSION_ID()
            });
        }

        preparedSetupData.helpers = helpers;
        preparedSetupData.permissions = permissions;
    }

    /// @inheritdoc IPluginSetup
    /// @dev This is a new release, so there is nothing to update to.
    function prepareUpdate(
        address,
        uint16,
        SetupPayload calldata
    )
        external
        view
        override
        returns (bytes memory initData, PreparedSetupData memory preparedSetupData)
    {}

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external view returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // Prepare permissions.
        uint256 helperLength = _payload.currentHelpers.length;
        if (helperLength != 1) {
            revert WrongHelpersArrayLength({length: helperLength});
        }

        permissions = new PermissionLib.MultiTargetPermission[](2);

        // Set permissions to be Revoked.
        permissions[0] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPDATE_VOTING_SETTINGS_PERMISSION_ID()
        });

        permissions[1] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _dao,
            who: _payload.plugin,
            condition: PermissionLib.NO_CONDITION,
            permissionId: EXECUTE_PERMISSION_ID
        });
    }

    /// @notice Retrieves the interface identifiers supported by the token contract.
    /// @dev It is crucial to verify if the provided token address represents a valid contract before using the below.
    /// @param token The token address
    function _getTokenInterfaceIds(address token) private view returns (bool[] memory) {
        bytes4[] memory interfaceIds = new bytes4[](3);
        interfaceIds[0] = type(IERC20Upgradeable).interfaceId;
        interfaceIds[1] = type(IVotesUpgradeable).interfaceId;
        interfaceIds[2] = type(IGovernanceWrappedERC20).interfaceId;
        return token.getSupportedInterfaces(interfaceIds);
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function _isERC20(address token) private view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this)))
        );
        return success && data.length == 0x20;
    }

    /// @notice Uses ERC-165 checks to see if a passed token appears to support
    /// the required interfaces for governance.
    /// @dev As an unsatisfactory check, this can be skipped.
    /// @param token The address of the governance token passed to 'prepareInstallation'.
    function missingInterface(address token) public view returns (bool) {
        // [0] = IERC20Upgradeable, [1] = IVotesUpgradeable, [2] = IGovernanceWrappedERC20
        bool[] memory supportedIds = _getTokenInterfaceIds(token);

        // If token supports none of them
        // it's simply ERC20 which gets checked by _isERC20
        // Currently, not a satisfiable check.
        bool isVanillaERC20 = (!supportedIds[0] && !supportedIds[1] && !supportedIds[2]);

        // If token supports IERC20, but neither
        // IVotes nor IGovernanceWrappedERC20, it needs wrapping.
        bool missingGovernance = (supportedIds[0] && !supportedIds[1] && !supportedIds[2]);

        return isVanillaERC20 || missingGovernance;
    }
}
