// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {IMembership} from "@aragon/osx-commons-contracts/src/plugin/extensions/membership/IMembership.sol";

// solhint-disable-next-line max-line-length
import {ProposalUpgradeable} from "@aragon/osx-commons-contracts/src/plugin/extensions/proposal/ProposalUpgradeable.sol";
import {DaoUnauthorized} from "@aragon/osx-commons-contracts/src/permission/auth/auth.sol";

import {PluginCloneable} from "@aragon/osx-commons-contracts/src/plugin/PluginCloneable.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {DAO, PermissionManager} from "@aragon/osx/core/dao/DAO.sol";

import {OAppReceiverUpgradeable, Origin} from "@oapp-upgradeable/oapp/OAppReceiverUpgradeable.sol";

import "utils/converters.sol";

import "forge-std/console2.sol";

/// @title AdminXChain
/// @author Aragon X
/// @notice The admin governance plugin giving execution permission on the DAO to a trusted relayer.
/// This allows a parent DAO on a foreign chain to control the DAO on this chain.
/// @custom:security-contact sirt@aragon.org
contract AdminXChain is IMembership, PluginCloneable, ProposalUpgradeable, OAppReceiverUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice The [ERC-165](https://eips.ethereum.org/EIPS/eip-165) interface ID of the contract.
    // bytes4 internal constant ADMIN_INTERFACE_ID =
    // this.initialize.selector ^ this.executeProposal.selector;

    /// @notice The ID of the permission required to call the `executeProposal` function.
    /// @dev This should be granted to the relayer.
    bytes32 public constant XCHAIN_EXECUTE_PERMISSION_ID = keccak256("XCHAIN_EXECUTE_PERMISSION");

    /// @notice Initializes the contract.
    /// @param _dao The associated DAO.
    /// @dev This method is required to support [ERC-1167](https://eips.ethereum.org/EIPS/eip-1167).
    function initialize(IDAO _dao, address _lzEndpoint) external initializer {
        __OAppCore_init(_lzEndpoint, address(_dao));
        __PluginCloneable_init(_dao);
        emit MembershipContractAnnounced({definingContract: address(_dao)});
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(PluginCloneable, ProposalUpgradeable) returns (bool) {
        return
            // _interfaceId == ADMIN_INTERFACE_ID ||
            _interfaceId == type(IMembership).interfaceId || super.supportsInterface(_interfaceId);
    }

    /// @inheritdoc IMembership
    function isMember(address _account) external view returns (bool) {
        return
            dao().hasPermission({
                _where: address(this),
                _who: _account,
                _permissionId: XCHAIN_EXECUTE_PERMISSION_ID,
                _data: bytes("")
            });
    }

    event XChainProposalExecuted(uint256 proposalId, uint srcChainId);

    /// @notice Internal function to execute a proposal.
    /// @param _proposalId The ID of the proposal to be executed.
    /// @param _actions The array of actions to be executed.
    /// @param _allowFailureMap A bitmap allowing the proposal to succeed, even if individual actions might revert. If the bit at index `i` is 1, the proposal succeeds even if the `i`th action reverts. A failure map value of 0 requires every action to not revert.
    /// @param _srcChainId The ID of the source chain.
    /// @return execResults The array with the results of the executed actions.
    /// @return failureMap The failure map encoding which actions have failed.
    /// @dev XChain proposals don't create their own proposal ID, they use the one from the source chain.
    function _executeXChainProposal(
        IDAO _dao,
        uint256 _proposalId,
        IDAO.Action[] memory _actions,
        uint256 _allowFailureMap,
        uint256 _srcChainId
    ) internal virtual returns (bytes[] memory execResults, uint256 failureMap) {
        (execResults, failureMap) = _dao.execute(bytes32(_proposalId), _actions, _allowFailureMap);
        emit XChainProposalExecuted({proposalId: _proposalId, srcChainId: _srcChainId});
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {
        // The DAO on this chain must manually set who can send messages on the remote chain
        address _who = bytes32ToAddress(_origin.sender);

        if (
            !dao().hasPermission({
                _where: address(this),
                _who: _who,
                _permissionId: XCHAIN_EXECUTE_PERMISSION_ID,
                _data: bytes("")
            })
        )
            revert DaoUnauthorized({
                dao: address(dao()),
                where: address(this),
                who: _who,
                permissionId: XCHAIN_EXECUTE_PERMISSION_ID
            });

        // decode the data
        (
            uint256 proposalId,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap,
            uint256 srcChainId
        ) = abi.decode(_message, (uint256, IDAO.Action[], uint256, uint256));

        _executeXChainProposal(dao(), proposalId, actions, allowFailureMap, srcChainId);
    }
}
