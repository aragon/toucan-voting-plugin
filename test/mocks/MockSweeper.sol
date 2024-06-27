// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {Sweeper, DaoAuthorizable} from "src/Sweeper.sol";
import {SweeperUpgradeable, DaoAuthorizableUpgradeable} from "src/SweeperUpgradeable.sol";

/// @dev Non abstract contract to test the abstract contract Sweeper
contract MockSweeper is Sweeper {
    constructor(address _dao) DaoAuthorizable(IDAO(_dao)) {}
}

/// @dev Non abstract contract to test the abstract contract SweeperUpgradeable
contract MockSweeperUpgradeable is SweeperUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao) public initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
    }
}
