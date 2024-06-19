// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";

/// Uber simple OApp that just sets a flag when it receives a message
/// useful for testing messages make it across, nothing else
contract MockOAppReceiver is OApp {
    bool public received;

    function _lzReceive(
        Origin calldata,
        bytes32,
        bytes calldata,
        address,
        bytes calldata
    ) internal override {
        received = true;
    }

    constructor(address _endpoint, address _delegate) OApp(_endpoint, _delegate) {}
}
