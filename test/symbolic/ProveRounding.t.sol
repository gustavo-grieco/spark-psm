// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";
import { PSM3Harness } from "test/unit/harnesses/PSM3Harness.sol";

// Rounding-tightness of the sUSDS conversion, against the real getSUsdsValue (both
// modes) via the repo's PSM3Harness. getSUsdsValue reads only the rate, so the real
// MockERC20s are fine here.
//
// This is exactly what the SwapExactOut fuzz tests assert —
// assertLe(roundUp - roundDown, 1): rounding never over-charges a user by more than
// a wei. A real fairness guarantee, independent of monotonicity (a monotonic but
// mis-rounded implementation still fails it), and provable here via plain division
// monotonicity ((a-1)/b <= a/b) without needing the exact closed form.
//
//   hevm test --match "prove_rounding" --abstract-arith --solver bitwuzla
contract ProveRounding is PSMTestBase {

    PSM3Harness psmHarness;

    function setUp() public override {
        super.setUp();
        psmHarness = new PSM3Harness(
            owner, address(usdc), address(usds), address(susds), address(mockRateProvider)
        );
    }

    // round-up exceeds round-down by at most 1 wei (rounding is tight / never
    // over-charges by more than a wei), for any conversion rate.
    function prove_rounding_susdsValue_tight(uint256 rate, uint256 amount) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(amount < 2**80);
        assert(psmHarness.getSUsdsValue(amount, true) <= psmHarness.getSUsdsValue(amount, false) + 1);
    }
}
