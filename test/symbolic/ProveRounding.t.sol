// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";
import { PSM3Harness } from "test/unit/harnesses/PSM3Harness.sol";

// Rounding-tightness of the sUSDS conversion, against the REAL conversion code
// exposed by the repo's own PSM3Harness (getSUsdsValue, both rounding modes).
// Deploys PSM3Harness on top of PSMTestBase exactly as Getters.t.sol does;
// getSUsdsValue reads only the rate (no balances), so the real MockERC20s are
// fine here.
//
// This is the property the SwapExactOut fuzz tests check as
// `assertLe(returnedAmountIn - amountIn, 1)`: the round-up result exceeds the
// round-down result by at most 1 wei, i.e. rounding never over-charges a user by
// more than a wei. It is independent of monotonicity (a monotonic-but-mis-rounded
// implementation would still fail it) and provable via division monotonicity
// (`(a-1)/b <= a/b`).
//
// NOTE on what is NOT here: the opposite direction (round-up >= round-down) and
// the swap round-trip / no-value-extraction property both come back `unknown`
// under the abstraction (they need a "consecutive-dividend floors differ by <=1"
// fact and const-factor cancellation respectively, neither of which the lemma set
// provides). They are recorded as misses in CANDIDATES.md rather than forced.
//
//   forge build --ast
//   hevm test --match "prove_rounding" --abstract-arith --solver bitwuzla --smt-timeout 120
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
