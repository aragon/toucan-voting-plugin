// SPDX-License-Identifier: AGPL-3.0-or-later

pragma solidity ^0.8.8;

import {GovernanceERC20} from "./GovernanceERC20.sol";
import {IDAO} from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

/// @title GovernanceERC20Burnable
/// @author Aragon Association
/// @notice Extends the Aragon GovernanceERC20 to allow for reducing the total supply of tokens
///         by burning them. This has implications for quorums and proposal thresholds.
/// @custom:security-contact sirt@aragon.org
contract GovernanceERC20Burnable is GovernanceERC20 {
    /// @notice Calls the burn function in the parent contract.
    bytes32 internal constant BURN_PERMISSION_ID = keccak256("BURN_PERMISSION");

    /// @notice Calls the initialize function in the parent contract.
    /// @param _dao The managing DAO.
    /// @param _name The name of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _symbol The symbol of the [ERC-20](https://eips.ethereum.org/EIPS/eip-20) governance token.
    /// @param _mintSettings The token mint settings struct containing the `receivers` and `amounts`.
    constructor(
        IDAO _dao,
        string memory _name,
        string memory _symbol,
        MintSettings memory _mintSettings
    ) GovernanceERC20(_dao, _name, _symbol, _mintSettings) {}

    /// @notice Burns a specific amount of tokens, decreasing the total supply.
    /// @dev    For voting, this has signifance for quorums and proposals.
    /// @param _amount The amount of token to be burned.
    function burn(uint256 _amount) external auth(BURN_PERMISSION_ID) {
        _burn(_msgSender(), _amount);
    }

    /// @notice Burns a specific amount of tokens from a specific account, decreasing the total supply.
    function burn(address _account, uint256 _amount) external auth(BURN_PERMISSION_ID) {
        _burn(_account, _amount);
    }
}
