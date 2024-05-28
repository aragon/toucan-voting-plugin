pragma solidity ^0.8.20;

import {IVoteContainer} from "@interfaces/IVoteContainer.sol";

library ComparisonTally {
    function eq(
        IVoteContainer.Tally memory a,
        IVoteContainer.Tally memory b
    ) internal pure returns (bool) {
        return a.yes == b.yes && a.no == b.no && a.abstain == b.abstain;
    }

    function sum(IVoteContainer.Tally memory tally) public pure returns (uint) {
        return tally.abstain + tally.yes + tally.no;
    }
}

library OverflowChecker {
    function overflows(IVoteContainer.Tally memory tally) internal pure returns (bool) {
        try ComparisonTally.sum(tally) {} catch Error(string memory) {
            return true;
        } catch (bytes memory) {
            return true;
        }

        return false;
    }
}
