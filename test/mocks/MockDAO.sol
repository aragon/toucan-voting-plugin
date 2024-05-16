pragma solidity ^0.8.20;

import "forge-std/console2.sol";

/// mocks IDAO for the governanceERC20 auth modifier
contract MockIDAO {
    function hasPermission(address, address, bytes32, bytes calldata) public view returns (bool) {
        // always pass
        return true;
    }

    function executeOne(address _to, bytes calldata _data) public payable {
        (bool success, ) = _to.call{value: msg.value}(_data);
        require(success, "executeOne: failed");
    }
}
