// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx/core/dao/IDAO.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {ProposalUpgradeable} from "@aragon/osx/core/plugin/proposal/ProposalUpgradeable.sol";
import {PluginUUPSUpgradeable} from "@aragon/osx/core/plugin/PluginUUPSUpgradeable.sol";
import {DAO} from "@aragon/osx/core/dao/DAO.sol";
import {HashiProverLib} from "@hashi/contracts/HashiProverLib.sol";
import {AccountAndStorageProof} from "@hashi/contracts/HashiProverStructs.sol";
import {SweeperUpgradeable} from "@utils/SweeperUpgradeable.sol";

/// @title AdminXChain
/// @author Aragon X
/// @notice The admin governance plugin giving execution permission on the DAO to a trusted relayer.
/// This allows a parent DAO on a foreign chain to control the DAO on this chain.
/// @dev The security model for this contract is entirely reliant on the configuration you choose within Hashi.
/// @custom:security-contact sirt@aragon.org
contract AdminXChain is PluginUUPSUpgradeable, ProposalUpgradeable, SweeperUpgradeable {
    using SafeCastUpgradeable for uint256;

    /// @notice Holders of this role are allowed to upgrade the contract
    bytes32 public constant OAPP_ADMINISTRATOR_ID = keccak256("OAPP_ADMINISTRATOR_ID");

    /// @notice Holders of this role are set actionRelayStorageKey
    bytes32 public constant SET_ACTION_RELAY_STORAGE_KEY = keccak256("SET_ACTION_RELAY_STORAGE_KEY");

    /// @notice Holders of this role are set shoyuBashi
    bytes32 public constant SET_SHOYU_BASHI = keccak256("SET_SHOYU_BASHI");

    /// @notice Thrown when an action has already been executed and cannot be repeated.
    error AlreadyExecuted();

    /// @notice Thrown when a wrong action relay is used for a given source chain id.
    error InvalidActionRelay();

    /// @notice Thrown when an invalid destination chain ID is provided.
    error InvalidDestinationChainId();

    /// @notice Thrown when a message is malformed or fails validation checks.
    error InvalidMessage();

    /// @notice Thrown when an incorrect storage key is used for accessing or verifying data.
    error InvalidStorageKey();

    /// @notice Emitted when a cross chain execution event is successfully processed.
    event XChainExecuted(
        uint256 indexed proposalId,
        uint256 indexed foreignCallId,
        uint256 indexed srcChainid,
        address sender,
        uint256 failureMap
    );

    /// @notice Emitted when ShoyuBashi is changed.
    event ShoyuBashiSet(address shoyuBashi);

    /// @notice Emitted when ShoyuBaactionRelayStorageKeyshi is changed.
    event ActionRelayStorageKeySet(bytes32 actionRelayStorageKey);

    /// @notice Metadata to identify a remote proposal. Logged on receipt.
    /// @param callId The ID of the proposal on the foreign chain. No guarantees of uniqueness.
    /// @param srcChainid The LayerZero foreign chain ID.
    /// @param sender The address of the sender on the foreign chain.
    /// @param received The timestamp when the proposal was received.
    struct XChainActionMetadata {
        uint256 callId;
        uint256 srcChainid;
        address sender;
        uint32 received;
    }

    /// @notice Store metadata from received actions against a globally unique proposal ID.
    /// @dev proposalId => XChainActionMetadata
    mapping(uint256 => XChainActionMetadata) internal _xChainActionMetadata;

    /// @notice Mapping used to avoid multiple execution of the same request.
    mapping(bytes32 => bool) internal _executedCommitments;

    /// @notice Mapping used to assign a specific action relay for a source chain id
    mapping(uint256 => address) public actionRelays;

    /// @notice value of the expected storage key of ActionRelay.
    bytes32 public actionRelayStorageKey;

    /// @notice address of the ShoyuBashi contract. This contract is used to define the oracles and the threshold used in Hashi.
    address public shoyuBashi;

    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract by setting the owner and the delegate to this address.
    /// @param _shoyuBashi The address of the ShoyuBashi contract
    function initialize(address _shoyuBashi) external initializer {
        // do not init PluginCloneable, as it would reinit DAOAuthorizable
        shoyuBashi = _shoyuBashi;
    }

    /// @notice Returns xChainActionMetadata for a given proposal ID as a struct.
    function xChainActionMetadata(uint256 _proposalId) external view returns (XChainActionMetadata memory) {
        return _xChainActionMetadata[_proposalId];
    }

    /// @notice Sets the storage key used to verify action relay commitments on the source chain.
    /// @dev This function requires the caller to have the `SET_ACTION_RELAY_STORAGE_KEY` authorization role.
    /// It updates the `actionRelayStorageKey` and emits an event to log this change.
    /// @param _actionRelayStorageKey The new storage key for the action relay.
    function setActionRelayStorageKey(bytes32 _actionRelayStorageKey) external auth(SET_ACTION_RELAY_STORAGE_KEY) {
        actionRelayStorageKey = _actionRelayStorageKey;
        emit ActionRelayStorageKeySet(_actionRelayStorageKey);
    }

    /// @notice Sets the address of the ShoyuBashi contract.
    /// @dev This function requires the caller to have the `SET_SHOYU_BASHI` authorization role.
    /// It updates the `shoyuBashi` address and emits an event to log the change.
    /// @param _shoyuBashi The new address for the ShoyuBashi contract.
    function setShoyuBashi(address _shoyuBashi) external auth(SET_SHOYU_BASHI) {
        shoyuBashi = _shoyuBashi;
        emit ShoyuBashiSet(_shoyuBashi);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        override(PluginUUPSUpgradeable, ProposalUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }

    /// @notice Entrypoint for executing a cross chain proposal.
    /// @param _proof contains the data to verify the proof.
    /// @param _message contains the execution instruction.
    function execute(AccountAndStorageProof calldata _proof, bytes calldata _message) internal {
        bytes32 commitment = keccak256(_message);
        if (_executedCommitments[commitment]) revert AlreadyExecuted();
        _executedCommitments[commitment] = true;

        bytes32 expectedCommitment = bytes32(HashiProverLib.verifyForeignStorage(_proof, shoyuBashi)[0]);
        if (commitment != expectedCommitment) revert InvalidMessage();

        (
            uint256 sourceChainId,
            uint256 destinationChainId,
            address sender,
            ,
            uint256 callId,
            IDAO.Action[] memory actions,
            uint256 allowFailureMap
        ) = abi.decode(_message, (uint256, uint256, address, uint256, uint256, IDAO.Action[], uint256));

        if (_proof.account != actionRelays[sourceChainId]) revert InvalidActionRelay();
        if (_proof.storageKeys[0] != actionRelayStorageKey) revert InvalidStorageKey();
        if (destinationChainId != block.chainid) revert InvalidDestinationChainId();

        // store the action metadata against the newly generated proposalId, ensuring it is unique
        uint256 proposalId = _createProposalId();
        _xChainActionMetadata[proposalId] =
            XChainActionMetadata(callId, sourceChainId, sender, block.timestamp.toUint32());

        // execute the action(s) as a proposal on the DAO
        (, uint256 failureMap) = dao().execute(bytes32(callId), actions, allowFailureMap);
        emit XChainExecuted(proposalId, callId, sourceChainId, sender, failureMap);
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
