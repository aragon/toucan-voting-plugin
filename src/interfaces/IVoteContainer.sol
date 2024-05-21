pragma solidity ^0.8.0;

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

library VoteAggregator {
    // can revert if votes are all above type(uint256).max / 3
    function sum(IVoteContainer.Tally memory votes) internal pure returns (uint256) {
        return votes.abstain + votes.yes + votes.no;
    }
}
