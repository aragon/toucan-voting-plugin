pragma solidity ^0.8.20;

/// this just allows a contract inheriting OApp to initialize without an error
/// use it if you don't intend to use any cross chain functionality
contract MockLzEndpointMinimal {
    function setDelegate(address _delegate) public {
        // do nothing
    }
}