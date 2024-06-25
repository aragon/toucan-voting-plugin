// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IOFT} from "@lz-oft/interfaces/IOFT.sol";
import {IOAppCore, ILayerZeroEndpointV2} from "@lz-oapp/interfaces/IOAppCore.sol";
import {IPluginSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/IPluginSetup.sol";
import {PluginUpgradeableSetup} from "@aragon/osx-commons-contracts/src/plugin/setup/PluginUpgradeableSetup.sol";
import {PermissionLib} from "@aragon/osx-commons-contracts/src/permission/PermissionLib.sol";
import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {OAppInitializer} from "@oapp-upgradeable/aragon-oapp/OAppInitializer.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";
import {GovernanceERC20VotingChain} from "@voting-chain/token/GovernanceERC20VotingChain.sol";

/// @title ToucanRelaySetup
/// @author Aragon X
/// @notice The setup contract of the `ToucanRelay` plugin.
/// @custom:security-contact sirt@aragon.org
contract ToucanRelaySetup is PluginUpgradeableSetup {
    using ProxyLib for address;

    /// @notice Thrown if the token is missing a required method for cross-chain communication.
    error TokenMissingMethod(address token, bytes4 selector);

    /// @notice Thrown if the token does not use a timestamp based clock.
    error TokenNotTimestamp(address token);

    /// @notice Thrown if the token name or symbol is empty.
    error InvalidTokenNameOrSymbol();

    /// @notice Thrown if the bridge is missing a required method for cross-chain communication.
    error BridgeMissingMethod(address bridge, bytes4 selector);

    /// @notice Thrown if the bridge is not the correct version.
    error InvalidBridge();

    /// @notice Thrown if the layerZero endpoint is invalid.
    error InvalidEndpoint();

    /// @notice Thrown if the DAO is not a delegate for the bridge OApp.
    error DaoNotDelegate(address dao, address delegate, address bridge);

    /// @notice Thrown if the token used in the bridge does not match the token provided.
    error IncorrectBridgeToken(address bridge, address token);

    /// @notice Thrown if the helpers length is incorrect.
    error IncorrectHelpersLength(uint8 expected, uint8 actual);

    /// @notice The ID of the permission required to call admin functions on the bridge and the relay.
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR");

    /// @notice address of the token bridge implementation.
    address public immutable bridgeBase;

    /// @notice address of the voting token implementation.
    address public immutable votingTokenBase;

    /// @notice The installation parameters for the `ToucanRelay` plugin.
    /// @param lzEndpoint The address of the LayerZero endpoint on this chain.
    /// @param bridge The address of the token bridge, can be a zero address to deploy a new one.
    /// @param token The address of the voting token, can be a zero address to deploy a new one.
    /// @param name The name of the voting token, can be an empty string if `token` is provided.
    /// @param symbol The symbol of the voting token, can be an empty string if `token` is provided.
    /// @param initializeCaller The address that will call the initializer, setting the peer after the
    /// execution chain contracts are setup.
    struct InstallationParams {
        address lzEndpoint;
        address bridge;
        address token;
        string name;
        string symbol;
    }

    /// @notice Sets the implementation contracts for the `ToucanRelay` plugin and helpers.
    /// @param _bridgeBase The address of the `OFTTokenBridge` implementation contract.
    /// @param _votingTokenBase The address of the `GovernanceERC20VotingChain` implementation contract.
    constructor(
        OFTTokenBridge _bridgeBase,
        GovernanceERC20VotingChain _votingTokenBase
    ) PluginUpgradeableSetup(address(new ToucanRelay())) {
        bridgeBase = address(_bridgeBase);
        votingTokenBase = address(_votingTokenBase);
    }

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

        address token = validateOrDeployToken(_dao, params);
        address bridge = validateOrDeployBridge(_dao, params.bridge, token, params.lzEndpoint);

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

        preparedSetupData.permissions = permissions;
        preparedSetupData.helpers = helpers;
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// --------- TOKEN ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~

    function validateOrDeployToken(
        address _dao,
        InstallationParams memory _params
    ) public returns (address) {
        if (_params.token == address(0)) {
            return deployToken(_dao, _params);
        } else {
            return validateToken(_dao, _params);
        }
    }

    function isEmpty(string memory _str) internal pure returns (bool) {
        return keccak256(abi.encode(_str)) == keccak256(abi.encode(""));
    }

    function deployToken(address _dao, InstallationParams memory _params) public returns (address) {
        if (isEmpty(_params.name) || isEmpty(_params.symbol)) {
            revert InvalidTokenNameOrSymbol();
        }
        return
            votingTokenBase.deployUUPSProxy(
                abi.encodeCall(
                    GovernanceERC20VotingChain.initialize,
                    (IDAO(_dao), _params.name, _params.symbol)
                )
            );
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

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- BRIDGE ----------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~

    function validateOrDeployBridge(
        address _dao,
        address _bridge,
        address _token,
        address _lzEndpoint
    ) public returns (address) {
        if (_bridge == address(0)) {
            return deployBridge(_dao, _token, _lzEndpoint);
        } else {
            return validateBridge(_dao, _bridge, _token, _lzEndpoint);
        }
    }

    function deployBridge(
        address _dao,
        address _token,
        address _lzEndpoint
    ) public returns (address) {
        return
            bridgeBase.deployUUPSProxy(
                abi.encodeCall(OFTTokenBridge.initialize, (_token, _lzEndpoint, _dao))
            );
    }

    function validateBridge(
        address _dao,
        address _bridge,
        address _token,
        address _lzEndpoint
    ) public view returns (address) {
        OFTTokenBridge bridge = OFTTokenBridge(_bridge);

        /// check the bridge is the correct OFT version
        try bridge.oftVersion() returns (bytes4 interfaceId, uint64 version) {
            if (interfaceId != type(IOFT).interfaceId || version != 1) {
                revert InvalidBridge();
            }
        } catch {
            revert BridgeMissingMethod(_bridge, bridge.oftVersion.selector);
        }

        /// check the token is the correct token
        try bridge.token() returns (address token) {
            if (token != _token) {
                revert IncorrectBridgeToken(_bridge, _token);
            }
        } catch {
            revert BridgeMissingMethod(_bridge, bridge.token.selector);
        }

        /// check the DAO is delegate for the bridge
        bytes memory callData = abi.encodeWithSignature("delegates(address)", _bridge);
        (bool success, bytes memory data) = (_lzEndpoint).staticcall(callData);
        if (!success) revert InvalidEndpoint();
        else {
            address delegate = abi.decode(data, (address));
            if (delegate != _dao) revert DaoNotDelegate(_dao, delegate, _bridge);
        }

        // all good - return the bridge
        return _bridge;
    }

    /// @inheritdoc IPluginSetup
    /// @dev This is a no-op as this is the first version of the plugin.
    function prepareUpdate(
        address _dao,
        uint16 _fromBuild,
        SetupPayload calldata _payload
    ) external returns (bytes memory initData, PreparedSetupData memory preparedSetupData) {}

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
