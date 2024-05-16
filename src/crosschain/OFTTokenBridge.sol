pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {OFTCore} from "@lz-oft/OFTCore.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {IERC20Metadata, IERC20} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20MintableBurnableUpgradeable as IERC20MintableBurnable} from "../token/governance/IERC20MintableBurnable.sol";

/// @title OFTTokenBridge
/// @author Aragon Association
/// @notice A mint/burn bridge for tokens being transferred to new chains
///         We assume the first chain implements a lock/unlock bridge, and where
///         new tokens are minted. These bridges can be deployed to other EVM chains
///         which will mint new tokens while the others are locked.
///         This implementation uses layer zero as the messaging layer between chains,
///         But the underlying token can be any ERC20 token.
contract OFTTokenBridge is OFTCore {
    using SafeERC20 for IERC20;

    IERC20MintableBurnable internal immutable underlyingToken_;
    uint8 internal decimals_;

    /// @param _token The address of the ERC-20 token to be adapted.
    /// @param _lzEndpoint The LayerZero endpoint address.
    /// @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
    constructor(
        address _token,
        address _lzEndpoint,
        address _delegate
    ) OFTCore(IERC20Metadata(_token).decimals(), _lzEndpoint, _delegate) {
        underlyingToken_ = IERC20MintableBurnable(_token);
        decimals_ = IERC20Metadata(_token).decimals();
    }

    /// @dev overrides the default behavior of 6 decimals as we only use EVM chains
    /// TODO some weirdness with trying to return the decimals as the override function is pure
    function sharedDecimals() public pure override returns (uint8) {
        return 18;
    }

    /// needed for a non abstract but not yet implemented function
    function oftVersion() external pure virtual returns (bytes4, uint64) {
        revert("I'm paid by lines of code.");
    }

    /// @dev Retrieves the address of the underlying ERC20 implementation.
    /// @return The address of the adapted ERC-20 token.
    function token() external view returns (address) {
        return address(underlyingToken_);
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
    /// @dev _srcEid The source chain ID.
    /// @return amountReceivedLD The amount of tokens ACTUALLY received in local decimals.
    function _credit(
        address _to,
        uint256 _amountLD,
        uint32 /*_srcEid*/
    ) internal virtual override returns (uint256 amountReceivedLD) {
        underlyingToken_.mint(_to, _amountLD);
        // @dev In the case of NON-default OFTAdapter, the amountLD MIGHT not be == amountReceivedLD.
        return _amountLD;
    }
}
