// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library Arr256Helper {
    function sum(uint256[] memory arr) internal pure returns (uint256) {
        uint256 _sum = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            _sum += arr[i];
        }
        return _sum;
    }

    function lte(uint256[] memory arr1, uint256 maxValue) internal pure returns (bool) {
        uint total = 0;
        uint tmp = 0;
        for (uint i = 0; i < arr1.length; i++) {
            // this is to allow overflow which we can check later
            unchecked {
                tmp += arr1[i];
            }
            // overflow
            if (tmp < total) return false;

            // we can safely assign tmp to total
            total = tmp;
            if (total > maxValue) return false;
        }
    }

    function isNonZero(uint256[] memory arr) internal pure returns (bool) {
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] > 0) {
                return false;
            }
        }
        return true;
    }
}
