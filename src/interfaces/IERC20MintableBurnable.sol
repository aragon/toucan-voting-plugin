// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20MintableUpgradeable} from "./IERC20MintableUpgradeable.sol";
import {IERC20BurnableUpgradeable} from "./IERC20BurnableUpgradeable.sol";

interface IERC20MintableBurnableUpgradeable is
    IERC20,
    IERC20MintableUpgradeable,
    IERC20BurnableUpgradeable
{}
