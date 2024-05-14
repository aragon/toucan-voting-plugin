pragma solidity 0.8.20;

import "@lz-oft/OFT.sol";

contract MyOFT is OFT {
    /*
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    */
    constructor(address _endpoint) OFT("MyOFT", "MOFT", _endpoint, address(1)) {}
}
