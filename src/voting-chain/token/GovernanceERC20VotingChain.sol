// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";
import {IERC20Burnable} from "@interfaces/IERC20Burnable.sol";

import {GovernanceERC20} from "@aragon/token-voting/ERC20/governance/GovernanceERC20.sol";

/// @title GovernanceERC20Voting chain
/// @author Aragon Association
/// @notice Extends the Aragon GovernanceERC20 to allow for reducing the total supply of tokens
/// by burning them. This has implications for quorums and proposal thresholds.
/// Also uses timestamp based voting. TODO: MORE INFO TO COME
/// @custom:security-contact sirt@aragon.org
contract GovernanceERC20VotingChain is GovernanceERC20, IERC20Burnable {
    /// @notice Calls the burn function in the parent contract.
    bytes32 public constant BURN_PERMISSION_ID = keccak256("BURN_PERMISSION");

    /// @notice Calls the initialize function in the parent contract.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @dev Mint settings must be empty on deployment as all tokens are expected to be minted via a cross-chain bridge.
    constructor(
        IDAO _dao,
        string memory _name,
        string memory _symbol
    ) GovernanceERC20(_dao, _name, _symbol, MintSettings(new address[](0), new uint256[](0))) {}

    /// @notice Burns a specific amount of tokens, decreasing the total supply.
    /// @dev For voting, this has signifance for quorums and proposals.
    /// @param _amount The amount of token to be burned.
    function burn(uint256 _amount) external auth(BURN_PERMISSION_ID) {
        _burn(_msgSender(), _amount);
    }

    /// @notice Burns a specific amount of tokens from a specific account, decreasing the total supply.
    /// @dev This does not require the other account's permission so be careful with granting this.
    function burn(address _account, uint256 _amount) external auth(BURN_PERMISSION_ID) {
        _burn(_account, _amount);
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
}
