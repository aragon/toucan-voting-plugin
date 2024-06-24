// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";

/// @title ToucanRelaySetup
/// @author Aragon X
/// @notice The setup contract of the `ToucanRelay` plugin.
/// @custom:security-contact sirt@aragon.org
contract ToucanRelaySetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    error TokenMissingMethod(address token, bytes4 selector);

    error TokenNotTimestamp(address token);

    // address of the token bridge
    address public immutable bridgeBase;

    // address of the voting token
    address public immutable votingTokenBase;

    struct InstallationParams {
        address lzEndpoint;
        address token;
        bool skipTokenValidation;
        address bridge;
        bool skipBridgeValidation;
    }

    constructor(
        OFTTokenBridge _bridgeBase,
        GovernanceERC20VotingChain _votingTokenBase
    ) PluginUpgradeableSetup(address(new ToucanRelay())) {
        bridgeBase = address(_bridgeBase);
        votingTokenBase = address(_votingTokenBase);
    }

    // /// @inheritdoc IPluginSetup
    // function prepareInstallation(
    //     address _dao,
    //     bytes calldata _data
    // ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
    //     /*
    //         Here we need to:

    //         1. Deploy the Relay
    //         2. Initialize the Relay
    //         3. Deploy the Voting Token (or link it)
    //         4. Deploy the bridge
    //         5. Grant the permissions for the relay, voting token and bridge
    //         6. Ensure the DAO can activate XChain by calling setPeer once the other side of the setup is complete OR allow an EOA to do so

    //     */
    // }

    /// @inheritdoc IPluginSetup
    function prepareInstallation(
        address _dao,
        bytes calldata _data
    ) external returns (address plugin, PreparedSetupData memory preparedSetupData) {
        // decode the data
        InstallationParams memory params = abi.decode(_data, (InstallationParams));

        // the helpers are the bridge and the voting token - let's ensure they exist
        // and pass our validations
        address[] memory helpers = new address[](2);
        address token = validateToken(_dao, params);
        address bridge = validateBridge(_dao, params);

        helpers[0] = token;
        helpers[1] = bridge;

        // deploy the relay
        plugin = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(ToucanRelay.initialize, (token, params.lzEndpoint, _dao))
        );

        // setup permissions
        PermissionLib.MultiTargetPermission[]
            memory permissions = new PermissionLib.MultiTargetPermission[](4);

        // bridge can mint and burn tokens
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
            permissionId: OFTTokenBridge(bridge).OAPP_ADMINISTRATOR_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: bridge
        });

        permissions[3] = PermissionLib.MultiTargetPermission({
            operation: PermissionLib.Operation.Grant,
            permissionId: ToucanRelay(plugin).OAPP_ADMINISTRATOR_ID(),
            condition: PermissionLib.NO_CONDITION,
            who: _dao,
            where: plugin
        });

        preparedSetupData.permissions = permissions;
        preparedSetupData.helpers = helpers;

        // 3. TODO setPeer still needs to be implemented on the other side
    }

    function validateToken(
        address,
        InstallationParams memory params
    ) public view returns (address) {
        // token needs to have burn and mint permissions
        // token should return balanceOf, mint, burn, getPastVotes
        // token should use a timestamp based clock
        GovernanceERC20VotingChain token = GovernanceERC20VotingChain(params.token);

        bytes[] memory calls = new bytes[](5);
        calls[0] = abi.encodeCall(token.BURN_PERMISSION_ID, ());
        calls[1] = abi.encodeCall(token.MINT_PERMISSION_ID, ());
        calls[2] = abi.encodeCall(token.balanceOf, (address(0)));
        calls[3] = abi.encodeCall(token.getPastVotes, (address(0), 0));
        calls[4] = abi.encodeCall(token.CLOCK_MODE, ());

        // check all the calls don't revert
        // need to be careful here as malcious address could be passed
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, ) = address(token).staticcall(calls[i]);
            if (!success) revert TokenMissingMethod(params.token, abi.decode(calls[i], (bytes4)));
        }

        // check the clock uses timestamps
        bytes32 clockModeHash = keccak256(abi.encodePacked(token.CLOCK_MODE()));
        bytes32 timestampHash = keccak256(abi.encodePacked("mode=timestamp"));
        if (!(clockModeHash == timestampHash)) revert TokenNotTimestamp(params.token);

        // all good - return the token
        return params.token;
    }

    function validateBridge(
        address _dao,
        InstallationParams memory params
    ) public view returns (address) {
        return params.bridge;
    }

    function _grantOAppAdminPermissions(
        address _dao,
        address _relay,
        address _bridge
    ) internal returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // 2. the bridge and the relay need to set the DAO as the admin
    }

    /// @inheritdoc IPluginSetup
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    ) external returns (bytes memory initData, PreparedSetupData memory preparedSetupData) {}

    /// @inheritdoc IPluginSetup
    function prepareUninstallation(
        address _dao,
        SetupPayload calldata _payload
    ) external returns (PermissionLib.MultiTargetPermission[] memory permissions) {}
}
