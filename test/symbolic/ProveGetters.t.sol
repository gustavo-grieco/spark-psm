// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";
import { PSM3Harness } from "test/unit/harnesses/PSM3Harness.sol";

// Properties of the precision/rate scaling primitives (_getUsdcValue,
// _getUsdsValue, _getSUsdsValue) exposed by the repo's own PSM3Harness — the
// building blocks of getAssetValue / convertToAssets. They read no balances
// (only the rate, for sUSDS), so the queries stay small.
//
//   forge build --ast
//   hevm test --match "prove_get" --abstract-arith --solver bitwuzla
contract ProveGetters is PSMTestBase {

    PSM3Harness psmHarness;

    function setUp() public override {
        super.setUp();
        psmHarness = new PSM3Harness(
            owner, address(usdc), address(usds), address(susds), address(mockRateProvider)
        );
    }

    // ---- monotonicity ----
    function prove_getUsdsValue_monotonic(uint256 a, uint256 b) public view {
        require(a <= b && b < 2**128);
        assert(psmHarness.getUsdsValue(a) <= psmHarness.getUsdsValue(b));
    }
    function prove_getUsdcValue_monotonic(uint256 a, uint256 b) public view {
        require(a <= b && b < 2**128);
        assert(psmHarness.getUsdcValue(a) <= psmHarness.getUsdcValue(b));
    }
    function prove_getSUsdsValue_roundDown_monotonic(uint256 rate, uint256 a, uint256 b) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a <= b && b < 2**80);
        assert(psmHarness.getSUsdsValue(a, false) <= psmHarness.getSUsdsValue(b, false));
    }
    function prove_getSUsdsValue_roundUp_monotonic(uint256 rate, uint256 a, uint256 b) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a <= b && b < 2**80);
        assert(psmHarness.getSUsdsValue(a, true) <= psmHarness.getSUsdsValue(b, true));
    }

    // ---- exact values (closed form) ----
    // The exact closed forms (getUsdsValue == x, getUsdcValue == x*1e12,
    // getSUsdsValue == x*rate/1e27) are proved in ProveOriginals.t.sol by
    // delegating to the repo's own UNMODIFIED Getters fuzz tests
    // (testFuzz_getUsdsValue / getUsdcValue / getSUsdsValue_roundDown), so there is
    // no hand-rewritten copy of those equalities here. This file keeps only the
    // monotonicity properties, which have no counterpart among the originals.
}
