// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";
import {PluginCloneable} from "@aragon/osx-commons-contracts/src/plugin/PluginCloneable.sol";
import {DAO, PermissionManager} from "@aragon/osx/core/dao/DAO.sol";

import {OAppReceiverUpgradeable, Origin} from "@oapp-upgradeable/oapp/OAppReceiverUpgradeable.sol";
import "@utils/converters.sol";
import "forge-std/console2.sol";

/// @title AdminXChain
/// @author Aragon X
/// @notice The admin governance plugin giving execution permission on the DAO to a trusted relayer.
/// This allows a parent DAO on a foreign chain to control the DAO on this chain.
/// @custom:security-contact sirt@aragon.org
contract AdminXChain is PluginCloneable, ProposalUpgradeable, OAppReceiverUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice The ID of the permission required to call the execution function.
    /// @dev This should be granted to the relayer.
    bytes32 public constant XCHAIN_EXECUTE_PERMISSION_ID = keccak256("XCHAIN_EXECUTE_PERMISSION");

    /// @notice Emitted when a cross chain execution event is successfully processed.
    event XChainExecuted(uint256 callId, uint srcChainId);

    /// @notice Initializes the contract by setting the owner and the delegate to this address.
    /// @param _dao The associated DAO.
    /// @param _lzEndpoint The address of the Layer Zero endpoint on this chain.abi
    function initialize(address _dao, address _lzEndpoint) external initializer {
        __OAppCore_init(_lzEndpoint, _dao);
        __PluginCloneable_init(IDAO(_dao));
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(PluginCloneable, ProposalUpgradeable) returns (bool) {
        return
            // _interfaceId == type(IMembership).interfaceId ||
            _interfaceId == type(OAppReceiverUpgradeable).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice Internal function to execute a proposal.
    /// @param _callId Unique identifier for this execution.
    /// @param _actions The array of actions to be executed.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param _srcChainId The ID of chain from which the XChain proposal originated.
    /// @return execResults The array with the results of the executed actions.
    /// @return failureMap The failure map encoding which actions have failed.
    /// @dev XChain proposals don't create their own proposal ID, they use the one from the source chain.
    function _executeXChain(
        IDAO _dao,
        uint256 _callId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        uint256 _srcChainId
    ) internal virtual returns (bytes[] memory execResults, uint256 failureMap) {
        (execResults, failureMap) = _dao.execute(bytes32(_callId), _actions, _allowFailureMap);
        emit XChainExecuted({callId: _callId, srcChainId: _srcChainId});
    }

    /// @notice Entrypoint for executing a cross chain proposal.
    /// @param _message contains the execution instruction.
    function _lzReceive(
        Origin calldata,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {
        // decode the data
        (
            uint256 proposalId,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap,
            uint256 srcChainId
        ) = abi.decode(_message, (uint256, IDAO.Action[], uint256, uint256));

        _executeXChain(dao(), proposalId, actions, allowFailureMap, srcChainId);
    }
}
