// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {ProxyLib} from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanRelayUpgradeable} from "@voting-chain/crosschain/ToucanRelayUpgradeable.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";

import {ProposalRelayer} from "@execution-chain/crosschain/ProposalRelayer.sol";
import {AdminXChain} from "@voting-chain/crosschain/AdminXChain.sol";

import {MockToucanRelay} from "test/mocks/MockToucanRelay.sol";
import {MockToucanRelayUpgradeable} from "test/mocks/MockToucanRelay.sol";
import {MockToucanReceiver} from "test/mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "test/mocks/MockToucanVoting.sol";

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
) returns (MockToucanRelayUpgradeable) {
    // deploy implementation
    address base = address(new MockToucanRelayUpgradeable());
    // encode the initalizer
    bytes memory data = abi.encodeCall(
        ToucanRelayUpgradeable.initialize,
        (_token, _lzEndpoint, _dao)
    );
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return MockToucanRelayUpgradeable(deployed);

    // return new MockToucanRelay({_token: _token, _lzEndpoint: _lzEndpoint, _dao: _dao});
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

function deployProposalRelayer(address _lzEndpoint, address _dao) returns (ProposalRelayer) {
    address base = address(new ProposalRelayer());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ProposalRelayer.initialize, (_lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return ProposalRelayer(deployed);
}

function deployAdminXChain(address _lzEndpoint, address _dao) returns (AdminXChain) {
    address base = address(new AdminXChain());
    // encode the initalizer
    bytes memory data = abi.encodeCall(AdminXChain.initialize, (IDAO(_dao), _lzEndpoint));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return AdminXChain(deployed);
}
