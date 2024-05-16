pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20MintableUpgradeable} from "./IERC20MintableUpgradeable.sol";

interface IERC20MintableBurnableUpgradeable is IERC20, IERC20MintableUpgradeable {
    function burn(uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;
}
