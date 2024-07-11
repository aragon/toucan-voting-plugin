// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {IOAppReceiver} from "@lz-oapp/interfaces/IOAppReceiver.sol";

import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";

import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {DaoUnauthorized} from "@aragon/osx/core/utils/auth.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {DAO, PermissionManager} from "@aragon/osx/core/dao/DAO.sol";

import {OAppReceiverUpgradeable, Origin} from "@oapp-upgradeable/aragon-oapp/OAppReceiverUpgradeable.sol";
import {SweeperUpgradeable} from "@utils/SweeperUpgradeable.sol";
import {bytes32ToAddress} from "@utils/converters.sol";

/// @title AdminXChain
/// @author Aragon X
/// @notice The admin governance plugin giving execution permission on the DAO to a trusted relayer.
/// This allows a parent DAO on a foreign chain to control the DAO on this chain.
/// @dev The security model for this contract is entirely reliant on the message broker, and that the peer is trusted.
/// In the case of LayerZero, we trust that both the origin EID and the sender address are validated, and that the peer is corectly set.
/// @custom:security-contact sirt@aragon.org
contract AdminXChain is
    PluginUUPSUpgradeable,
    ProposalUpgradeable,
    OAppReceiverUpgradeable,
    SweeperUpgradeable
{
    using SafeCastUpgradeable for uint256;

    /// @notice Emitted when a cross chain execution event is successfully processed.
    event XChainExecuted(
        uint256 indexed proposalId,
        uint256 indexed foreignCallId,
        uint32 indexed srcEid,
        address sender,
        uint256 failureMap
    );

    /// @notice Metadata to identify a remote proposal. Logged on receipt.
    /// @param callId The ID of the proposal on the foreign chain. No guarantees of uniqueness.
    /// @param srcEid The LayerZero foreign chain ID.
    /// @param sender The address of the sender on the foreign chain.
    /// @param received The timestamp when the proposal was received.
    struct XChainActionMetadata {
        uint256 callId;
        uint32 srcEid;
        address sender;
        uint32 received;
    }

    /// @notice Store metadata from received actions against a globally unique proposal ID.
    /// @dev proposalId => XChainActionMetadata
    mapping(uint256 => XChainActionMetadata) internal _xChainActionMetadata;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract by setting the owner and the delegate to this address.
    /// @param _dao The associated DAO.
    /// @param _lzEndpoint The address of the Layer Zero endpoint on this chain.abi
    function initialize(address _dao, address _lzEndpoint) external initializer {
        __OAppCore_init(_lzEndpoint, _dao);
        // do not init PluginCloneable, as it would reinit DAOAuthorizable
    }

    /// @notice Returns xChainActionMetadata for a given proposal ID as a struct.
    function xChainActionMetadata(
        uint256 _proposalId
    ) external view returns (XChainActionMetadata memory) {
        return _xChainActionMetadata[_proposalId];
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view override(PluginUUPSUpgradeable, ProposalUpgradeable) returns (bool) {
        return
            _interfaceId == type(IOAppReceiver).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice Entrypoint for executing a cross chain proposal.
    /// @param _origin contains the source endpoint and sender address, passed from Layer Zero.
    /// @param _message contains the execution instruction.
    /// @dev The security model for this function is entirely reliant on the message broker, and that the peer is trusted.
    /// @dev TODO: storing the message hash is an alternative option that could then be used to limit the calldata passed
    /// between chains. This could then be re-construted and executed on the receiving chain.
    function _lzReceive(
        Origin calldata _origin,
        bytes32 /* _guid */,
        bytes calldata _message,
        address /* _executor */,
        bytes calldata /* _extraData */
    ) internal override {
        (uint256 callId, IDAO.Action[] memory actions, uint256 allowFailureMap) = abi.decode(
            _message,
            (uint256, IDAO.Action[], uint256)
        );
        address sender = bytes32ToAddress(_origin.sender);

        // store the action metadata against the newly generated proposalId, ensuring it is unique
        uint proposalId = _createProposalId();
        _xChainActionMetadata[proposalId] = XChainActionMetadata(
            callId,
            _origin.srcEid,
            sender,
            block.timestamp.toUint32()
        );

        // execute the action(s) as a proposal on the DAO
        (, uint256 failureMap) = dao().execute(bytes32(callId), actions, allowFailureMap);
        emit XChainExecuted(proposalId, callId, _origin.srcEid, sender, failureMap);
    }

    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    /// -------- UPGRADE FUNCTIONS --------
    /// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    /// @dev Keeps permissions lean by giving OApp administrator the ability to upgrade.
    /// The alternative would be to define a separate permission which adds complexity.
    /// As this contract is upgradeable, this can be changed in the future.
    function _authorizeUpgrade(address) internal override auth(OAPP_ADMINISTRATOR_ID) {}

    /// @dev Gap to reserve space for future storage layout changes.
    uint256[49] private __gap;
}
