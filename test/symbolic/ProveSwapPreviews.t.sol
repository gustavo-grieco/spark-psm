// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";

// Symbolic counterparts of the per-pair swap fuzz tests (SwapExactIn/ExactOut).
// Inherits PSMTestBase, so the setup is identical to those fuzz tests (same real
// new PSM3(...), MockERC20 tokens, mockRateProvider), and previewSwap* reads no
// balances — the quote is a pure function of (amount, rate, precision).
//
// Bounds follow the uniform uint128 proof budget (see ProveOriginals): every raw
// input is required <= type(uint128).max and nothing else, except the structural
// constraints a property needs — the monotonicity ordering (a1 <= a2, r1 <= r2)
// and rate != 0 on the legs where the symbolic rate is a divisor (converting TO
// susds, or susds as the ExactOut input leg; a zero rate there is a division by
// zero, not a price).
//
// The ExactIn legs are covered by exact closed forms in ProveOriginals (an exact
// value implies amount-monotonicity), so this file keeps only what the originals do
// NOT cover, each a real guarantee in its own right:
//   1. Amount-monotonicity of the ExactOut (round-up) quotes. Their closed form is a
//      ceilDiv over an abstract product, out of reach as an exact equality; but
//      monotonicity already rules out the exploit — requesting more output can never
//      cost less input, so no one can underpay by splitting or reordering a swap.
//   2. Rate-direction monotonicity for every sUSDS leg: the quote moves the correct
//      way as the rate changes (rate in the numerator => nondecreasing; rate as the
//      divisor => nonincreasing), so a rate update can't silently invert pricing.
//   3. The usds<->susds round-trip: swapping out and back never returns more than
//      you put in (value-conservation), even without the exact per-leg amounts.
//
//   hevm test --match "prove_swap" --abstract-arith --solver bitwuzla
contract ProveSwapPreviews is PSMTestBase {

    // ---- previewSwapExactOut (round up): amount-monotonicity ----
    // Each prove_ names the testFuzz_* it mirrors and that test's closed-form amount.

    // testFuzz_swapExactOut_usdsToUsdc: amountIn = amountOut * 1e12
    function prove_swapExactOut_usdsToUsdc(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(usds), address(usdc), a1)
            <= psm.previewSwapExactOut(address(usds), address(usdc), a2));
    }

    // testFuzz_swapExactOut_usdsToSUsds: amountIn = amountOut * rate / 1e27 (round up, +/-1)
    function prove_swapExactOut_usdsToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate <= type(uint128).max);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(usds), address(susds), a1)
            <= psm.previewSwapExactOut(address(usds), address(susds), a2));
    }

    // testFuzz_swapExactOut_usdcToUsds: amountIn = amountOut / 1e12 (round up, +/-1)
    function prove_swapExactOut_usdcToUsds(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(usdc), address(usds), a1)
            <= psm.previewSwapExactOut(address(usdc), address(usds), a2));
    }

    // testFuzz_swapExactOut_usdcToSUsds: amountIn = amountOut * rate / 1e27 / 1e12 (round up)
    function prove_swapExactOut_usdcToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate <= type(uint128).max);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(usdc), address(susds), a1)
            <= psm.previewSwapExactOut(address(usdc), address(susds), a2));
    }

    // testFuzz_swapExactOut_susdsToUsds: amountIn = amountOut * 1e27 / rate (round up)
    function prove_swapExactOut_susdsToUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate != 0 && rate <= type(uint128).max);   // rate divides
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(susds), address(usds), a1)
            <= psm.previewSwapExactOut(address(susds), address(usds), a2));
    }

    // testFuzz_swapExactOut_susdsToUsdc: amountIn = amountOut * 1e27 / rate * 1e12 (round up)
    function prove_swapExactOut_susdsToUsdc(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate != 0 && rate <= type(uint128).max);   // rate divides
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= type(uint128).max);
        assert(psm.previewSwapExactOut(address(susds), address(usdc), a1)
            <= psm.previewSwapExactOut(address(susds), address(usdc), a2));
    }

    // ---- rate-direction monotonicity (2-state: read at r1, raise rate to r2) ----
    // sUSDS->usds output is amountIn*rate/1e27, so it INCREASES with the rate
    // (mul-mono + div-mono).
    function prove_swapExactIn_susdsToUsds_rate_increasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(x <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(susds), address(usds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(susds), address(usds), x);
        assert(o1 <= o2);
    }
    // usds->sUSDS output is amountIn*1e27/rate, so it DECREASES as the rate rises
    // (rate is the divisor — divisor-anti-monotonicity).
    function prove_swapExactIn_usdsToSUsds_rate_decreasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 != 0 && r1 <= r2 && r2 <= type(uint128).max);   // rate divides
        require(x <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(usds), address(susds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(usds), address(susds), x);
        assert(o2 <= o1);
    }
    // usdc->sUSDS output is amountIn*1e27/rate*1e12, DECREASES as the rate rises.
    function prove_swapExactIn_usdcToSUsds_rate_decreasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 != 0 && r1 <= r2 && r2 <= type(uint128).max);   // rate divides
        require(x <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(usdc), address(susds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(usdc), address(susds), x);
        assert(o2 <= o1);
    }
    // sUSDS->usdc output is amountIn*rate/1e27/1e12, INCREASES with the rate.
    function prove_swapExactIn_susdsToUsdc_rate_increasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(x <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(susds), address(usdc), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(susds), address(usdc), x);
        assert(o1 <= o2);
    }
    // ExactOut, sUSDS in: required input is amountOut*1e27/rate (ceil), so it
    // DECREASES as the rate rises (rate is the divisor — divisor-anti-mono).
    function prove_swapExactOut_susdsToUsds_rate_decreasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 != 0 && r1 <= r2 && r2 <= type(uint128).max);   // rate divides
        require(y <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(susds), address(usds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(susds), address(usds), y);
        assert(i2 <= i1);
    }
    function prove_swapExactOut_susdsToUsdc_rate_decreasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 != 0 && r1 <= r2 && r2 <= type(uint128).max);   // rate divides
        require(y <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(susds), address(usdc), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(susds), address(usdc), y);
        assert(i2 <= i1);
    }
    // ExactOut, sUSDS out: required input is amountOut*rate/1e27 (ceil), so it
    // INCREASES with the rate (mul-mono + ceil).
    function prove_swapExactOut_usdsToSUsds_rate_increasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(y <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(usds), address(susds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(usds), address(susds), y);
        assert(i1 <= i2);
    }
    function prove_swapExactOut_usdcToSUsds_rate_increasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r2 <= type(uint128).max);
        require(y <= type(uint128).max);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(usdc), address(susds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(usdc), address(susds), y);
        assert(i1 <= i2);
    }

    // ---- stateless swap round-trip (value-conservation) ----
    // Swapping out and straight back never returns more than you put in — the
    // stateless heart of "a swap never reduces pool value", through the real
    // previewSwapExactIn. Only the usds<->susds round-trip proves: it cancels by the
    // SYMBOLIC rate (an abstract product), so the div×mul link (a/rate)*rate <= a
    // fires. The constant-leg round-trips cancel via a native *1e12 / *1e27, which the
    // abstract-mul-only div×mul link can't bridge — they stay unknown.
    function prove_roundtrip_usds_susds(uint256 rate, uint256 x) public {
        require(rate != 0 && rate <= type(uint128).max);   // rate divides on the way out
        mockRateProvider.__setConversionRate(rate);
        require(x <= type(uint128).max);
        uint256 out = psm.previewSwapExactIn(address(usds), address(susds), x);
        // Derived-operand budget (same idiom as totalAssets() in ProveRealPSM3): the
        // intermediate quote is x*1e27/rate, which a tiny rate pushes past uint128;
        // the return hop multiplies it by the rate, and that abstract product's
        // no-overflow guard needs both factors within the uint128 budget.
        require(out <= type(uint128).max);
        uint256 back = psm.previewSwapExactIn(address(susds), address(usds), out);
        assert(back <= x);
    }
}
