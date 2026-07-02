// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";
import { PSM3Harness } from "test/unit/harnesses/PSM3Harness.sol";

// Properties of the precision/rate scaling primitives (_getUsdcValue,
// _getUsdsValue, _getSUsdsValue) exposed by the repo's own PSM3Harness — the
// building blocks of getAssetValue / convertToAssets. They read no balances
// (only the rate, for sUSDS), so the queries stay small.
//
//   hevm test --match "prove_get" --abstract-arith --solver bitwuzla
contract ProveGetters is PSMTestBase {

    PSM3Harness psmHarness;

    function setUp() public override {
        super.setUp();
        psmHarness = new PSM3Harness(
            owner, address(usdc), address(usds), address(susds), address(mockRateProvider)
        );
    }

    // Round-up sUSDS monotonicity (more in never values to less out). The round-DOWN
    // getters have exact closed forms in ProveOriginals, which already imply their
    // monotonicity; the round-up form is a ceilDiv, out of reach as an exact
    // equality, so monotonicity is the most we prove for it.
    function prove_getSUsdsValue_roundUp_monotonic(uint256 rate, uint256 a, uint256 b) public {
        require(rate <= type(uint128).max);
        mockRateProvider.__setConversionRate(rate);
        require(a <= b && b <= type(uint128).max);
        assert(psmHarness.getSUsdsValue(a, true) <= psmHarness.getSUsdsValue(b, true));
    }

    // Rate-direction monotonicity (2-state: read at r1, raise rate to r2). getSUsdsValue
    // is amount*rate/1e27, so it is nondecreasing in the rate (mul-mono + div-mono) —
    // a higher backing ratio never values a fixed holding lower.
    function prove_getSUsdsValue_roundDown_rate_monotonic(uint256 a, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(a <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 v1 = psmHarness.getSUsdsValue(a, false);
        mockRateProvider.__setConversionRate(r2);
        uint256 v2 = psmHarness.getSUsdsValue(a, false);
        assert(v1 <= v2);
    }
    function prove_getSUsdsValue_roundUp_rate_monotonic(uint256 a, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(a <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 v1 = psmHarness.getSUsdsValue(a, true);
        mockRateProvider.__setConversionRate(r2);
        uint256 v2 = psmHarness.getSUsdsValue(a, true);
        assert(v1 <= v2);
    }

    // The exact closed forms (getUsdsValue == x, getUsdcValue == x*1e12,
    // getSUsdsValue == x*rate/1e27) are delegated to the repo's own fuzz tests in
    // ProveOriginals — no copy here.
}
