pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MyOFT} from "src/token/MyOFT.sol";

contract LzEndpointMock {
    function setDelegate(address _delegate) public {}
}

contract TestMyOFT is Test {
    function testItWorks() public {
        // OFT is a contract that inherits from ERC20
        // and has a constructor that takes two strings
        // and sets the name and symbol of the token
        // to those strings
        // We can deploy it and check that the name and symbol
        // are set correctly
        MyOFT myOFT = new MyOFT(address(new LzEndpointMock()));
    }
}
