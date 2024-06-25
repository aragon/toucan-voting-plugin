// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {OApp} from "@lz-oapp/OApp.sol";
import {OFT} from "@lz-oft/OFT.sol";
import {Origin} from "@lz-oapp/interfaces/IOAppReceiver.sol";
import {OAppUpgradeable} from "@oapp-upgradeable/aragon-oapp/OAppUpgradeable.sol";
import {OFTUpgradeable} from "@oapp-upgradeable/aragon-oft/OFTUpgradeable.sol";

/// OApp and OFT in the layerZero and Aragon implementations
/// Ours are upgradeable/proxiable and use the OSx permissions system

contract MockOApp is OApp {
    constructor(address _lzEndpoint, address _dao) OApp(_lzEndpoint, _dao) {}

    // do nothing
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata /*_message*/,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {}
}

contract MockOFT is OFT {
    constructor(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) OFT(_name, _symbol, _lzEndpoint, _delegate) {}

    // do nothing
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata /*_message*/,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {}
}

contract MockOAppUpgradeable is OAppUpgradeable {
    function initialize(address _lzEndpoint, address _dao) public initializer {
        __OApp_init(_lzEndpoint, _dao);
    }

    // do nothing
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata /*_message*/,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {}
}

contract MockOFTUpgradeable is OFTUpgradeable {
    function initialize(
        string memory _name,
        string memory _symbol,
        address _lzEndpoint,
        address _delegate
    ) public initializer {
        __OFT_init(_name, _symbol, _lzEndpoint, _delegate);
    }

    // do nothing
    function _lzReceive(
        Origin calldata /* _origin */,
        bytes32 /* _guid */,
        bytes calldata /*_message*/,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {}
}
