// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

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

import {ProxyLib} from "@libs/ProxyLib.sol";
import {ToucanVoting} from "./ToucanVoting.sol";
import {IToucanVoting} from "./IToucanVoting.sol";

/// @title ToucanVotingSetup
/// @author Aragon X - 2022-2023
/// @notice The setup contract of the `ToucanVoting` plugin.
/// @dev v1.3 (Release 1, Build 3)
/// @custom:security-contact sirt@aragon.org
contract ToucanVotingSetup is PluginSetup {
    using Address for address;
    using ERC165Checker for address;
    using ProxyLib for address;

    /// @notice The identifier of the `EXECUTE_PERMISSION` permission.
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
    error TokenNotContract(address token);

    /// @notice Thrown if token address is not ERC20.
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

    /// @return The address of the `ToucanVoting` implementation contract.
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
            GovernanceERC20.MintSettings memory mintSettings
        ) = abi.decode(
                _data,
                (IToucanVoting.VotingSettings, TokenSettings, GovernanceERC20.MintSettings)
            );

        address token = tokenSettings.addr;
        bool deployToken = token == address(0);

        // Prepare helpers.
        address[] memory helpers = new address[](1);

        // If we pass an existing token, we need to check if it is an erc20votes
        // And whether it can be wrapped
        if (!deployToken) {
            if (!token.isContract()) revert TokenNotContract(token);
            if (!isERC20(token)) revert TokenNotERC20(token);
            if (!isGovernanceToken(token)) {
                // User already has a token. We need to wrap it in
                // GovernanceWrappedERC20 in order to make the token
                // include governance functionality.
                token = governanceWrappedERC20Base.deployMinimalProxy(
                    abi.encodeCall(
                        GovernanceWrappedERC20.initialize,
                        (
                            IERC20Upgradeable(tokenSettings.addr),
                            tokenSettings.name,
                            tokenSettings.symbol
                        )
                    )
                );
            }
            // if no token is passed, we deploy a new GovernanceERC20 token
        } else {
            // Create a new GovernanceERC20 token.
            token = governanceERC20Base.deployMinimalProxy(
                abi.encodeCall(
                    GovernanceERC20.initialize,
                    (IDAO(_dao), tokenSettings.name, tokenSettings.symbol, mintSettings)
                )
            );
        }

        // Prepare and deploy plugin proxy.
        plugin = address(tokenVotingBase).deployUUPSProxy(
            abi.encodeCall(ToucanVoting.initialize, (IDAO(_dao), votingSettings, token))
        );

        // Prepare permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](deployToken ? 4 : 3);

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

        // Grant the upgrade plugin permission to the DAO.
        // Technically redundant as the DAO already has root.
        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            where: plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });

        // if the token was created in this setup, grant mint permission to the dao
        if (deployToken) {
            permissions[3] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                where: token,
                who: _dao,
                condition: PermissionLib.NO_CONDITION,
                permissionId: GovernanceERC20(token).MINT_PERMISSION_ID()
            });
        }

        // set the return data for the prepared setup
        helpers[0] = token;

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

        permissions = new PermissionLib.MultiTargetPermission[](3);

        // Set permissions to be Revoked.
        // We don't revoke mint as the DAO may still need to mint tokens.
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

        permissions[2] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Revoke,
            where: _payload.plugin,
            who: _dao,
            condition: PermissionLib.NO_CONDITION,
            permissionId: tokenVotingBase.UPGRADE_PLUGIN_PERMISSION_ID()
        });
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20 token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @param token The token address
    function isERC20(address token) public view returns (bool) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeCall(IERC20Upgradeable.balanceOf, (address(this)))
        );
        return success && data.length == 0x20;
    }

    /// @notice Unsatisfiably determines if the contract is an ERC20Votes token.
    /// @dev It's important to first check whether token is a contract prior to this call.
    /// @dev Calling some of precompile addresses will cause this to return true.
    /// TODO: is this an issue we care about.
    /// @param token The token address
    function isGovernanceToken(address token) public view returns (bool) {
        (bool getVotesSuccess, bytes memory getVotesData) = token.staticcall(
            abi.encodeWithSelector(IVotesUpgradeable.getVotes.selector, address(this))
        );
        (bool getPastVotesSuccess, bytes memory getPastVotesData) = token.staticcall(
            abi.encodeWithSelector(
                IVotesUpgradeable.getPastVotes.selector,
                address(this),
                block.number - 1
            )
        );
        (bool getPastTotalSupplySuccess, bytes memory getPastTotalSupplyData) = token.staticcall(
            abi.encodeWithSelector(IVotesUpgradeable.getPastTotalSupply.selector, block.number - 1)
        );
        return
            getVotesSuccess &&
            getVotesData.length == 0x20 &&
            getPastVotesSuccess &&
            getPastVotesData.length == 0x20 &&
            getPastTotalSupplySuccess &&
            getPastTotalSupplyData.length == 0x20;
    }
}
