// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

/// @title TallyMath
/// @author Aragon
/// @notice Simple math utilities for structs containing yes, no, and abstain votes.
library TallyMath {
    /// @return Whether two tallies are equal for all pairwise values.
    function eq(
        IVoteContainer.Tally memory a,
        IVoteContainer.Tally memory b
    ) internal pure returns (bool) {
        return a.yes == b.yes && a.no == b.no && a.abstain == b.abstain;
    }

    /// @return The sum of two tallies inside a new tally.
    /// @dev This can revert on overflow if the total exceeds the maximum uint.
    function add(
        IVoteContainer.Tally memory a,
        IVoteContainer.Tally memory b
    ) internal pure returns (IVoteContainer.Tally memory) {
        return
            IVoteContainer.Tally({
                yes: a.yes + b.yes,
                no: a.no + b.no,
                abstain: a.abstain + b.abstain
            });
    }

    /// @return The difference of two tallies inside a new tally.
    /// @dev This can revert on underflow if the total exceeds the maximum uint.
    function sub(
        IVoteContainer.Tally memory a,
        IVoteContainer.Tally memory b
    ) internal pure returns (IVoteContainer.Tally memory) {
        return
            IVoteContainer.Tally({
                yes: a.yes - b.yes,
                no: a.no - b.no,
                abstain: a.abstain - b.abstain
            });
    }

    /// @return The product of a tally and a scalar inside a new tally.
    function div(
        IVoteContainer.Tally memory a,
        uint256 divisor
    ) internal pure returns (IVoteContainer.Tally memory) {
        return
            IVoteContainer.Tally({
                yes: a.yes / divisor,
                no: a.no / divisor,
                abstain: a.abstain / divisor
            });
    }

    /// @return The difference of two tallies inside a new tally.
    /// @dev This can revert ib overflow if the total exceeds the maximum uint.
    function sum(IVoteContainer.Tally memory tally) internal pure returns (uint) {
        return tally.abstain + tally.yes + tally.no;
    }

    /// @return Whether all items in the tally are zero.
    /// @dev Checking if each vote is zero is safer than summing due to potential overflow.
    function isZero(IVoteContainer.Tally memory tally) internal pure returns (bool) {
        return tally.yes == 0 && tally.no == 0 && tally.abstain == 0;
    }
}

library OverflowChecker {
    using TallyMath for IVoteContainer.Tally;

    function overflows(IVoteContainer.Tally memory tally) internal pure returns (bool) {
        // Check for overflow when adding yes and no votes
        if (tally.yes > type(uint256).max - tally.no) {
            return true;
        }
        // Check for overflow when adding yes + no and abstain votes
        uint256 yesNoSum = tally.yes + tally.no;
        if (yesNoSum > type(uint256).max - tally.abstain) {
            return true;
        }
        return false;
    }
}
