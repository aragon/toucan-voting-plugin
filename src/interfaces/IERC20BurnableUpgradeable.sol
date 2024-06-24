// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface IERC20BurnableUpgradeable {
    function burn(address _from, uint256 _amount) external;

    function burn(uint256 _amount) external;
}
