// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

/* solhint-disable max-line-length */

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IERC20BurnableUpgradeable} from "@interfaces/IERC20BurnableUpgradeable.sol";
import {IERC20MintableUpgradeable} from "@interfaces/IERC20MintableUpgradeable.sol";
import {IERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/IVotesUpgradeable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {DaoAuthorizableUpgradeable} from "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";

/* solhint-enable max-line-length */

/// @title GovernanceERC20VotingChain
/// @author Aragon X
/// @notice An [OpenZeppelin `Votes`](https://docs.openzeppelin.com/contracts/4.x/api/governance#Votes)
/// compatible [ERC-20](https://eips.ethereum.org/EIPS/eip-20) token, used for voting and managed by a DAO.
/// @dev Designed to be use in a cross chain context with timestamp based voting.
/// @dev Adds burning functionality to the token. Tokens can be removed from the total supply
/// by burning them. This has implications for quorums and proposal thresholds.
/// Also uses timestamp based voting as opposed to block based voting - making it suitable for cross-chain voting.
/// @dev There are no initial mints - bridge contracts should be given mint/burn permissions.
/// @custom:security-contact sirt@aragon.org
contract GovernanceERC20VotingChain is
    IERC20MintableUpgradeable,
    IERC20BurnableUpgradeable,
    Initializable,
    ERC165Upgradeable,
    ERC20VotesUpgradeable,
    DaoAuthorizableUpgradeable
{
    /// @notice The permission identifier to mint new tokens.
    bytes32 public constant MINT_PERMISSION_ID = keccak256("MINT_PERMISSION");

    /// @notice The permission identifier to burn tokens.
    bytes32 public constant BURN_PERMISSION_ID = keccak256("BURN_PERMISSION");

    /// @notice Calls the initialize function.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    constructor(IDAO _dao, string memory _name, string memory _symbol) {
        initialize(_dao, _name, _symbol);
    }

    /// @notice Initializes the contract and mints tokens to a list of receivers.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    function initialize(IDAO _dao, string memory _name, string memory _symbol) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __DaoAuthorizableUpgradeable_init(_dao);
    }

    /// @notice Checks if this or the parent contract supports an interface by its ID.
    /// @param _interfaceId The ID of the interface.
    /// @return Returns `true` if the interface is supported.
    function supportsInterface(bytes4 _interfaceId) public view virtual override returns (bool) {
        return
            _interfaceId == type(IERC20Upgradeable).interfaceId ||
            _interfaceId == type(IERC20PermitUpgradeable).interfaceId ||
            _interfaceId == type(IERC20MetadataUpgradeable).interfaceId ||
            _interfaceId == type(IVotesUpgradeable).interfaceId ||
            _interfaceId == type(IERC20MintableUpgradeable).interfaceId ||
            _interfaceId == type(IERC20BurnableUpgradeable).interfaceId ||
            super.supportsInterface(_interfaceId);
    }

    /// @notice Mints tokens to an address.
    /// @param to The address receiving the tokens.
    /// @param amount The amount of tokens to be minted.
    function mint(address to, uint256 amount) external override auth(MINT_PERMISSION_ID) {
        _mint(to, amount);
    }

    /// @notice Burns a specific amount of tokens from a specific account, decreasing the total supply.
    /// @dev This does not require the other account's permission so be careful with granting this.
    /// @param from The address of the account owning the tokens.
    /// @param amount The amount of tokens to be burned.
    function burn(address from, uint256 amount) external auth(BURN_PERMISSION_ID) {
        _burn(from, amount);
    }

    /// @notice Burns a specific amount of tokens from the caller, decreasing the total supply.
    /// @dev Still requires the BURN_PERMISSION_ID permission.
    function burn(uint256 amount) external override auth(BURN_PERMISSION_ID) {
        _burn(_msgSender(), amount);
    }

    /// @notice Override the clock to use block.timestamp in place of block.number.
    /// @dev Syncing blocks between chains is difficult, so we use timestamps instead.
    /// https://docs.openzeppelin.com/contracts/4.x/governance#timestamp_based_governance
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice OZ Convention to show timestamp based voting is used.
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    // https://forum.openzeppelin.com/t/self-delegation-in-erc20votes/17501/12?u=novaknole
    /// @inheritdoc ERC20VotesUpgradeable
    function _afterTokenTransfer(address from, address to, uint256 amount) internal override {
        super._afterTokenTransfer(from, to, amount);

        // Automatically turn on delegation on mint/transfer but only for the first time.
        if (to != address(0) && numCheckpoints(to) == 0 && delegates(to) == address(0)) {
            _delegate(to, to);
        }
    }
}
