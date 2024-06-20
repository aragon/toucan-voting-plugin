// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.00;

function bytes32ToAddress(bytes32 _b) pure returns (address) {
    return address(uint160(uint256(_b)));
}

function addressToBytes32(address _addr) pure returns (bytes32) {
    return bytes32(uint256(uint160(_addr)));
}
