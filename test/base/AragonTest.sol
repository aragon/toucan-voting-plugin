// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import {PluginSetup, IPluginSetup} from "@aragon/osx/framework/plugin/setup/PluginSetup.sol";

import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AragonTest {
    /// @notice manually creates a mock dao
    /// @param _initalOwner The initial owner of the DAO having the `ROOT_PERMISSION_ID` permission.
    function _createMockDAO(address _initalOwner) internal returns (DAO) {
        DAO _dao = DAO(payable(new ERC1967Proxy(address(new DAO()), bytes(""))));
        string memory _daoURI = "ipfs://";
        _dao.initialize({
            _metadata: bytes(""),
            _initialOwner: _initalOwner,
            _trustedForwarder: address(0),
            daoURI_: _daoURI
        });
        return _dao;
    }

    function createMockDAO(address _initialOwner) public returns (DAO) {
        return _createMockDAO(_initialOwner);
    }

    function createMockDAO() public returns (DAO) {
        return _createMockDAO(address(this));
    }
}
