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
        helpers[0] = _validateToken(_dao, params);
        helpers[1] = _validateBridge(_dao, params);

        // deploy the relay
        plugin = IMPLEMENTATION.deployUUPSProxy(
            abi.encodeCall(ToucanRelay.initialize, (helpers[0], params.lzEndpoint, _dao))
        );

        // setup permissions

        // 1. the bridge needs mint and burn permissions on the token

        // 2. the bridge and the relay need to set the DAO as the delegate/owner/admin
        // 3. TODO setPeer still needs to be implemented on the other side

        preparedSetupData.permissions = new PermissionLib.MultiTargetPermission[](3);
    }

    function _validateToken(
        address _dao,
        InstallationParams memory params
    ) internal view returns (address) {
        return params.token;
    }

    function _validateBridge(
        address _dao,
        InstallationParams memory params
    ) internal view returns (address) {
        return params.bridge;
    }

    function _grantMintBurnPermissions(
        address _dao,
        address _token,
        address _bridge
    ) internal returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        IDAO dao = IDAO(_dao);
        GovernanceERC20VotingChain token = GovernanceERC20VotingChain(_token);

        //  Check if the bridge has the mint permission
        bool hasMint = dao.hasPermission({
            _who: _bridge,
            _where: _token,
            _permissionId: token.MINT_PERMISSION_ID(),
            _data: bytes("")
        });

        bool hasBurn = dao.hasPermission({
            _who: _bridge,
            _where: _token,
            _permissionId: token.BURN_PERMISSION_ID(),
            _data: bytes("")
        });

        if (hasMint) {
            permissions[0] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                permissionId: token.MINT_PERMISSION_ID(),
                condition: PermissionLib.NO_CONDITION,
                who: _bridge,
                where: _token
            });
        }

        if (hasBurn) {
            permissions[1] = PermissionLib.MultiTargetPermission({
                operation: PermissionLib.Operation.Grant,
                permissionId: token.BURN_PERMISSION_ID(),
                condition: PermissionLib.NO_CONDITION,
                who: _bridge,
                where: _token
            });
        }
    }

    function _grantOAppAdminPermissions(
        address _dao,
        address _relay,
        address _bridge
    ) internal returns (PermissionLib.MultiTargetPermission[] memory permissions) {
        // 2. the bridge and the relay need to set the DAO as the delegate/owner/admin
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
