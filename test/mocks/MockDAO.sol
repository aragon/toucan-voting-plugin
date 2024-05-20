pragma solidity ^0.8.20;

import "forge-std/console2.sol";

/// mocks IDAO for the governanceERC20 auth modifier
contract MockDAOSimplePermission {
    function hasPermission(address, address, bytes32, bytes calldata) public view returns (bool) {
        // always pass
        return true;
    }
}
