// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {ToucanRelay} from "src/crosschain/toucanRelay/ToucanRelay.sol";
import {MockToucanRelay} from "test/mocks/MockToucanRelay.sol";

/// adding deployers behind free functions allows us to change proxy patterns easily

function deployToucanRelay(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (ToucanRelay) {
    return new ToucanRelay({_token: _token, _lzEndpoint: _lzEndpoint, _dao: _dao});
}

function deployMockToucanRelay(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (MockToucanRelay) {
    return new MockToucanRelay({_token: _token, _lzEndpoint: _lzEndpoint, _dao: _dao});
}
