// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {ToucanRelay} from "src/voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "src/execution-chain/crosschain/ToucanReceiver.sol";
import {MockToucanRelay} from "test/mocks/MockToucanRelay.sol";
import {MockToucanReceiver} from "test/mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "test/mocks/MockToucanVoting.sol";
import {GovernanceOFTAdapter} from "src/execution-chain/crosschain/GovernanceOFTAdapter.sol";

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

function deployToucanReceiver(
    address _governanceToken,
    address _lzEndpoint,
    address _dao,
    address _votingPlugin
) returns (ToucanReceiver) {
    return
        new ToucanReceiver({
            _governanceToken: _governanceToken,
            _lzEndpoint: _lzEndpoint,
            _dao: _dao,
            _votingPlugin: _votingPlugin
        });
}

function deployMockToucanReceiver(
    address _governanceToken,
    address _lzEndpoint,
    address _dao,
    address _votingPlugin
) returns (MockToucanReceiver) {
    return
        new MockToucanReceiver({
            _governanceToken: _governanceToken,
            _lzEndpoint: _lzEndpoint,
            _dao: _dao,
            _votingPlugin: _votingPlugin
        });
}

function deployMockToucanVoting() returns (MockToucanVoting) {
    return new MockToucanVoting();
}

function deployGovernanceOFTAdapter(
    address _token,
    address _voteProxy,
    address _lzEndpoint,
    address _dao
) returns (GovernanceOFTAdapter) {
    return
        new GovernanceOFTAdapter({
            _token: _token,
            _voteProxy: _voteProxy,
            _lzEndpoint: _lzEndpoint,
            _dao: _dao
        });
}
