// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {ProxyLib} from "@libs/ProxyLib.sol";
import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";

import {GovernanceOFTAdapter} from "@execution-chain/crosschain/GovernanceOFTAdapter.sol";
import {ToucanRelay} from "@voting-chain/crosschain/ToucanRelay.sol";
import {ToucanReceiver} from "@execution-chain/crosschain/ToucanReceiver.sol";

import {ActionRelay} from "@execution-chain/crosschain/ActionRelay.sol";
import {AdminXChain} from "@voting-chain/crosschain/AdminXChain.sol";
import {OFTTokenBridge} from "@voting-chain/crosschain/OFTTokenBridge.sol";

import {MockToucanRelay, MockToucanRelayLzMock} from "@mocks/MockToucanRelay.sol";
import {MockToucanReceiver} from "@mocks/MockToucanReceiver.sol";
import {MockToucanVoting} from "@mocks/MockToucanVoting.sol";
import {MockTokenBridge} from "@mocks/MockTokenBridge.sol";
import {MockActionRelay} from "@mocks/MockActionRelay.sol";
import {MockOAppUpgradeable as MockOApp, MockOFTUpgradeable as MockOFT} from "@mocks/MockOApp.sol";

/// adding deployers behind free functions allows us to change proxy patterns easily

function deployToucanRelay(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (ToucanRelay) {
    // deploy implementation
    address base = address(new ToucanRelay());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ToucanRelay.initialize, (_token, _lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return ToucanRelay(deployed);
}

function deployMockToucanRelay(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (MockToucanRelay) {
    // deploy implementation
    address base = address(new MockToucanRelay());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ToucanRelay.initialize, (_token, _lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return MockToucanRelay(deployed);
}

function deployMockToucanRelayLzMock(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (MockToucanRelayLzMock) {
    // deploy implementation
    address base = address(new MockToucanRelayLzMock());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ToucanRelay.initialize, (_token, _lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return MockToucanRelayLzMock(deployed);
}

function deployToucanReceiver(
    address _governanceToken,
    address _lzEndpoint,
    address _dao,
    address _votingPlugin
) returns (ToucanReceiver) {
    // deploy implementation
    address base = address(new ToucanReceiver());
    // encode the initalizer
    bytes memory data = abi.encodeCall(
        ToucanReceiver.initialize,
        (_governanceToken, _lzEndpoint, _dao, _votingPlugin)
    );
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return ToucanReceiver(payable(deployed));
}

function deployMockToucanReceiver(
    address _governanceToken,
    address _lzEndpoint,
    address _dao,
    address _votingPlugin
) returns (MockToucanReceiver) {
    // deploy implementation
    address base = address(new MockToucanReceiver());
    // encode the initalizer
    bytes memory data = abi.encodeCall(
        ToucanReceiver.initialize,
        (_governanceToken, _lzEndpoint, _dao, _votingPlugin)
    );
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return MockToucanReceiver(payable(deployed));
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
    address base = address(new GovernanceOFTAdapter());
    // encode the initalizer
    bytes memory data = abi.encodeCall(
        GovernanceOFTAdapter.initialize,
        (_token, _voteProxy, _lzEndpoint, _dao)
    );

    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return GovernanceOFTAdapter(deployed);
}

function deployActionRelay(address _lzEndpoint, address _dao) returns (ActionRelay) {
    address base = address(new ActionRelay());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ActionRelay.initialize, (_lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return ActionRelay(deployed);
}

function deployMockActionRelay(address _lzEndpoint, address _dao) returns (MockActionRelay) {
    address base = address(new MockActionRelay());
    // encode the initalizer
    bytes memory data = abi.encodeCall(ActionRelay.initialize, (_lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return MockActionRelay(deployed);
}

function deployAdminXChain(address _lzEndpoint, address _dao) returns (AdminXChain) {
    address base = address(new AdminXChain());
    // encode the initalizer
    bytes memory data = abi.encodeCall(AdminXChain.initialize, (_dao, _lzEndpoint));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return AdminXChain(payable(deployed));
}

function deployTokenBridge(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (OFTTokenBridge) {
    address base = address(new OFTTokenBridge());
    // encode the initalizer
    bytes memory data = abi.encodeCall(OFTTokenBridge.initialize, (_token, _lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return OFTTokenBridge(deployed);
}

function deployMockTokenBridge(
    address _token,
    address _lzEndpoint,
    address _dao
) returns (MockTokenBridge) {
    address base = address(new MockTokenBridge());
    // encode the initalizer
    bytes memory data = abi.encodeCall(OFTTokenBridge.initialize, (_token, _lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployUUPSProxy(base, data);
    return MockTokenBridge(deployed);
}

function deployMockOApp(address _lzEndpoint, address _dao) returns (MockOApp) {
    address base = address(new MockOApp());
    // encode the initalizer
    bytes memory data = abi.encodeCall(MockOApp.initialize, (_lzEndpoint, _dao));
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return MockOApp(deployed);
}

function deployMockOFT(
    string memory _name,
    string memory _symbol,
    address _lzEndpoint,
    address _delegate
) returns (MockOFT) {
    address base = address(new MockOFT());
    // encode the initalizer
    bytes memory data = abi.encodeCall(
        MockOFT.initialize,
        (_name, _symbol, _lzEndpoint, _delegate)
    );
    // deploy and return the proxy
    address deployed = ProxyLib.deployMinimalProxy(base, data);
    return MockOFT(deployed);
}
