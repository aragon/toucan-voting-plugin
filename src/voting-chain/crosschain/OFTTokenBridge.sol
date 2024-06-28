// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IOFT} from "@lz-oft/interfaces/IOFT.sol";
import {IERC20MintableBurnableUpgradeable as IERC20MintableBurnable} from "@interfaces/IERC20MintableBurnable.sol";

import {SafeERC20Upgradeable as SafeERC20} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

import {OFTCoreUpgradeable} from "@oapp-upgradeable/aragon-oft/OFTCoreUpgradeable.sol";

/// @title OFTTokenBridge
/// @author Aragon Association
/// @notice A mint/burn bridge for tokens being transferred to new chains
/// We assume the first chain implements a lock/unlock bridge, and where
/// new tokens are minted. These bridges can be deployed to other EVM chains
/// which will mint new tokens while the others are locked.
/// This implementation uses layer zero as the messaging layer between chains,
/// But the underlying token can be any ERC20 token that allows for minting/burning.
/// TODO some sanity checks: iface chacks and sending values > uint224 across the network
/// TODO Operator guide on shared decimals
/// @dev The OFT Standard implements a shared decimals model which limits the amount of precision
/// that can be sent across chains.
contract OFTTokenBridge is OFTCoreUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice UPGRADES removed immutablility.
    IERC20MintableBurnable internal underlyingToken_;

    constructor() {
        _disableInitializers();
    }

    /// @param _token The address of the ERC-20 token to be adapted.
    /// @param _lzEndpoint The LayerZero endpoint address.
    /// @param _dao The delegate capable of making OApp configurations inside of the endpoint.
    function initialize(address _token, address _lzEndpoint, address _dao) external initializer {
        __OFTCore_init(IERC20Metadata(_token).decimals(), _lzEndpoint, _dao);
        underlyingToken_ = IERC20MintableBurnable(_token);
    }

    /// @notice Retrieves interfaceID and the version of the OFT.
    /// @return interfaceId The interface ID for IOFT.
    /// @return version Indicates a cross-chain compatible msg encoding with other OFTs.
    /// @dev If a new feature is added to the OFT cross-chain msg encoding, the version will be incremented.
    /// ie. localOFT version(x,1) CAN send messages to remoteOFT version(x,1)
    function oftVersion() external pure virtual returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @dev Retrieves the address of the underlying ERC20 implementation.
    /// @return The address of the adapted ERC-20 token.
    function token() external view returns (address) {
        return address(underlyingToken_);
    }

    /// @notice In a shared decimal model, lower bits of the uint will be cleaned to allow for compact
    /// representation of the amount. This function calculates the amount of dust that will be removed.
    /// @dev This can be the minAmountLD when calling the send function on the OFT.
    /// @param _amountLD The amount of tokens to send in local decimals.
    /// @return The amount after removing the dust.
    function previewRemoveDust(uint256 _amountLD) external view returns (uint256) {
        return _removeDust(_amountLD);
    }

    /// @notice Indicates whether the OFT contract requires approval of the 'token()' to send.
    /// @return requiresApproval Needs approval of the underlying token implementation.
    function approvalRequired() external pure virtual returns (bool) {
        return true;
    }

    /// @notice Burns tokens from the sender's specified balance, ie. pull method.
    /// @param _amountLD The amount of tokens to send in local decimals.
    /// @param _minAmountLD The minimum amount to send in local decimals.
    /// @param _dstEid The destination chain ID.
    /// @return amountSentLD The amount sent in local decimals.
    /// @return amountReceivedLD The amount received in local decimals on the remote.
    /// @dev msg.sender will need to approve this _amountLD of tokens to be burned by this contract.
    /// @dev Because of the shared decimals model, amountSentLD will be less than _amountLD if there are nonzero
    /// values in the lower bits of the uint. Set minAmountLD accordingly using the `previewRemoveDust` function.
    function _debit(
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        (amountSentLD, amountReceivedLD) = _debitView(_amountLD, _minAmountLD, _dstEid);
        underlyingToken_.burn(msg.sender, amountSentLD);
    }

    /// @notice Credits tokens to the specified address by minting
    /// @param _to The address to credit the tokens to.
    /// @param _amountLD The amount of tokens to credit in local decimals.
    /// @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        underlyingToken_.mint(_to, _amountLD);
        return _amountLD;
    }

    /// @notice Returns the address of the implementation contract in the [proxy storage slot](https://eips.ethereum.org/EIPS/eip-1967) slot the [UUPS proxy](https://eips.ethereum.org/EIPS/eip-1822) is pointing to.
    /// @return The address of the implementation contract.
    function implementation() public view returns (address) {
        return _getImplementation();
    }

    /// @notice Internal method authorizing the upgrade of the contract via the [upgradeability mechanism for UUPS proxies](https://docs.openzeppelin.com/contracts/4.x/api/proxy#UUPSUpgradeable) (see [ERC-1822](https://eips.ethereum.org/EIPS/eip-1822)).
    function _authorizeUpgrade(address) internal virtual override auth(OAPP_ADMINISTRATOR_ID) {}

    /// @dev Added for future storage slots.
    uint256[49] private __gap;
}
