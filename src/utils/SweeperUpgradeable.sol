// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {DaoAuthorizableUpgradeable} from "@aragon/osx/core/plugin/dao-authorizable/DaoAuthorizableUpgradeable.sol";

/// @title SweeperUpgradeable
/// @author Aragon
/// @notice A contract that sends stored funds to a known DAO.
/// @dev This can be used to sweep tokens or ETH sent to the DAO either by accident or as part
/// of a refund mechanism (i.e. for crosschain transactions with surplus destination gas).
abstract contract SweeperUpgradeable is DaoAuthorizableUpgradeable {
    using SafeERC20 for IERC20;

    /// @notice Grants permission to collect refunds.
    /// @dev Refund collection involves transferring ETH or passing in unknown tokens.
    /// As such the refund collector must be a trusted address.
    bytes32 public constant SWEEP_COLLECTOR_ID = keccak256("SWEEP_COLLECTOR");

    /// @notice Emitted when a refund fails.
    /// @param amount The amount of the refund that failed. Will be 0 if there was nothing to refund.
    /// @param token The token that was attempted to be refunded. Will be the zero address if the refund was in Native.
    /// @param dao The DAO address that the refund was attempted to be sent to.
    error RefundFailed(uint256 amount, address token, address dao);

    /// @notice Emitted when there is nothing to refund.
    /// @param token The token that was attempted to be refunded. Will be the zero address if the refund was in Native.
    /// @param dao The DAO address that the refund was attempted to be sent to.
    error NothingToRefund(address token, address dao);

    /// @notice Sends all stored Native to the DAO.
    /// @dev While the DAO is trusted, sending Native on the EVM hits the fallback function
    /// which is a common reentrancy vector.
    /// As such, this function is restricted to a trusted address.
    function sweepNative() external auth(SWEEP_COLLECTOR_ID) {
        address dao = address(dao());
        uint balance = address(this).balance;

        if (balance == 0) revert NothingToRefund(address(0), dao);

        (bool success, ) = payable(address(dao)).call{value: balance}("");
        if (!success) revert RefundFailed(balance, address(0), dao);
    }

    /// @notice Sends the balance of the passed token to the DAO.
    /// @param _token The token to sweep.
    /// @dev This function is restricted to a trusted address as the token is completely unknown.
    function sweepToken(address _token) external auth(SWEEP_COLLECTOR_ID) {
        // transfer to DAO
        address dao = address(dao());
        uint balance = IERC20(_token).balanceOf(address(this));

        if (balance == 0) revert NothingToRefund(_token, dao);

        IERC20(_token).safeTransfer(dao, balance);
    }

    /// @notice Fallback function to accept ETH.
    receive() external payable virtual {}
}
