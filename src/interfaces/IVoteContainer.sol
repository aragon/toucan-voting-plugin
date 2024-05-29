// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

/// TODO: should this be shared with Majority voting?
/// or should be split it out so majority voting can inherit
interface IVoteContainer {
    /// @notice A container for the proposal vote tally
    /// @param abstain The number of abstain votes casted.
    /// @param yes The number of yes votes casted.
    /// @param no The number of no votes casted.
    struct Tally {
        uint256 abstain;
        uint256 yes;
        uint256 no;
    }
}
