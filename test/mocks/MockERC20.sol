// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20("MockERC20", "MERC") {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
