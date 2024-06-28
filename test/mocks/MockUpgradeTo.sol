// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.8;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @dev Featherweight implementation to check if a contract has been upgraded.
contract MockUpgradeTo is UUPSUpgradeable {
    bool public immutable v2Upgraded = true;

    function _authorizeUpgrade(address) internal pure override {}

    function implementation() public view returns (address) {
        return _getImplementation();
    }
}
