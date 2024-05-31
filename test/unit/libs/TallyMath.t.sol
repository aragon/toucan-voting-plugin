// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IVoteContainer} from "@interfaces/IVoteContainer.sol";
import {TallyMath, OverflowChecker} from "@libs/TallyMath.sol";

contract TallyMathTest is Test, IVoteContainer {
    using TallyMath for Tally;
    using OverflowChecker for Tally;

    function testFuzz_eq(uint a, uint b, uint c) public pure {
        vm.assume(a < type(uint256).max);

        Tally memory tallyA = Tally(a, b, c);
        Tally memory tallyB = Tally(a, b, c);

        assertTrue(tallyA.eq(tallyB));

        Tally memory tallyC = Tally(a + 1, b, c);

        assertFalse(tallyA.eq(tallyC));
    }

    function testFuzz_add(uint a, uint b, uint c, uint d, uint e, uint f) public pure {
        // prevent overflow
        vm.assume(a <= type(uint256).max - d);
        vm.assume(b <= type(uint256).max - e);
        vm.assume(c <= type(uint256).max - f);

        Tally memory tallyA = Tally({yes: a, no: b, abstain: c});
        Tally memory tallyB = Tally({yes: d, no: e, abstain: f});
        Tally memory sum = tallyA.add(tallyB);

        assertTrue(sum.yes == a + d);
        assertTrue(sum.no == b + e);
        assertTrue(sum.abstain == c + f);
    }

    function testFuzz_sub(uint a, uint b, uint c, uint d, uint e, uint f) public pure {
        // prevent underflow
        vm.assume(a >= d);
        vm.assume(b >= e);
        vm.assume(c >= f);

        Tally memory tallyA = Tally({yes: a, no: b, abstain: c});
        Tally memory tallyB = Tally({yes: d, no: e, abstain: f});
        Tally memory sub = tallyA.sub(tallyB);

        assertTrue(sub.yes == a - d);
        assertTrue(sub.no == b - e);
        assertTrue(sub.abstain == c - f);
    }

    function testFuzz_div(uint a, uint b, uint c, uint divisor) public {
        Tally memory tally = Tally({yes: a, no: b, abstain: c});

        if (divisor == 0) vm.expectRevert();
        Tally memory div = tally.div(divisor);

        assertTrue(div.yes == a / divisor);
        assertTrue(div.no == b / divisor);
        assertTrue(div.abstain == c / divisor);
    }

    function testFuzz_sum(uint a, uint b, uint c) public pure {
        Tally memory tally = Tally(a, b, c);
        vm.assume(!tally.overflows());

        assertEq(tally.sum(), a + b + c);
    }

    function testFuzz_isZero(uint a, uint b, uint c) public pure {
        vm.assume(a > 0 || b > 0 || c > 0);

        Tally memory tally = Tally(a, b, c);
        assertFalse(tally.isZero());

        Tally memory zeroTally = Tally(0, 0, 0);
        assertTrue(zeroTally.isZero());
    }

    function test_overflows() public pure {
        uint a = type(uint256).max;
        uint b = 1;
        uint c = 0;

        Tally memory tally = Tally(a, b, c);
        assertTrue(tally.overflows());

        Tally memory noOverflowTally = Tally(a - 1, b, c);
        assertFalse(noOverflowTally.overflows());
    }
}
