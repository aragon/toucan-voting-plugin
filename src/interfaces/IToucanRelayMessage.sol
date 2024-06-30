// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {IVoteContainer} from "./IVoteContainer.sol";

/// @title IToucanRelayMessage
/// @notice Interface for the cross chain voting messages to be encoded.
interface IToucanRelayMessage {
    /// @param votingChainId The block.chainid of the voting chain.
    /// @param proposalRef The proposal reference to vote on, encoded as a uint256.
    /// @dev This should uniquely identify the proposal on the execution chain
    /// but does not have to be the same as the proposalId.
    /// In Toucan voting, we also include relevant proposal data in the reference.
    /// @param votes The votes to be relayed.
    struct ToucanVoteMessage {
        uint256 votingChainId;
        uint256 proposalRef;
        IVoteContainer.Tally votes;
    }
}
