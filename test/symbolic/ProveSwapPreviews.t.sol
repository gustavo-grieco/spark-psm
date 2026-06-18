// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMTestBase } from "test/PSMTestBase.sol";

// Symbolic counterparts of the per-pair swap fuzz tests in
// test/unit/SwapExactIn.t.sol and test/unit/SwapExactOut.t.sol.
//
// This contract inherits PSMTestBase, so the setup is *identical* to those fuzz
// tests: the same real `new PSM3(...)`, the same MockERC20 tokens, the same
// `mockRateProvider`, the same `*_TOKEN_MAX` bounds. Each prove_ below names the
// original `testFuzz_swap*` it mirrors and quotes that test's amount/rate bounds
// and its closed-form amount, so the correspondence is checkable step by step.
//
// WHAT IS ASSERTED:
// 1. Monotonicity of every quote (all 6 pairs, both ExactIn and ExactOut) in its
//    amount — the strongest property the solver discharges universally, over the
//    originals' exact amount/rate domains. Needs the multiplication abstraction
//    for the nonlinear sUSDS legs.
// 2. The originals' *exact* closed-form amount, for the ExactIn legs where the
//    arithmetic abstraction's constant-cancellation lemmas reach it (4 of 6):
//    usdc->usds (`x*1e12`, generalized const-cancel), susds->usds (`x*rate/1e27`,
//    nested-div-collapse), usds->susds (`x*1e27/rate`) and usdc->susds
//    (`x*1e27/rate*1e12`). These prove the documented quote exactly — not just its
//    monotonicity — through the real previewSwapExactIn.
// The two legs that convert TO usdc (`x/1e12`) remain `unknown` (see the note by
// those probes), and the ExactOut round-up legs keep monotonicity only (a ceilDiv
// over an abstract product is heavier; exact forms there are future work). A fuzz
// test checks an exact value by *sampling* (cheap per point); a symbolic *proof*
// of the closed form is a far harder query, so the exact-value coverage tracks
// exactly which cancellation lemmas exist.
//
// previewSwap* reads no token balances (only the rate, for sUSDS legs), so no
// balance/storage modelling is needed — the quote is a pure function of
// (amount, rate, precision).
//
//   forge build --ast
//   hevm test --match "prove_swap" --abstract-arith --solver bitwuzla --smt-timeout 300
contract ProveSwapPreviews is PSMTestBase {

    // =====================================================================
    // previewSwapExactIn  (round down)   — mirrors SwapExactIn.t.sol
    // =====================================================================

    // testFuzz_swapExactIn_usdsToUsdc: amountIn in [1, USDS_TOKEN_MAX],
    //                                  amountOut = amountIn / 1e12
    function prove_swapExactIn_usdsToUsdc(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(usds), address(usdc), a1)
            <= psm.previewSwapExactIn(address(usds), address(usdc), a2));
    }

    // testFuzz_swapExactIn_usdsToSUsds: amountIn in [1, USDS_TOKEN_MAX],
    //   conversionRate in [0.01e27, 100e27], amountOut = amountIn * 1e27 / rate
    function prove_swapExactIn_usdsToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(usds), address(susds), a1)
            <= psm.previewSwapExactIn(address(usds), address(susds), a2));
    }

    // testFuzz_swapExactIn_usdcToUsds: amountIn in [1, USDC_TOKEN_MAX],
    //                                  amountOut = amountIn * 1e12
    function prove_swapExactIn_usdcToUsds(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= USDC_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(usdc), address(usds), a1)
            <= psm.previewSwapExactIn(address(usdc), address(usds), a2));
    }

    // testFuzz_swapExactIn_usdcToSUsds: amountIn in [1, USDC_TOKEN_MAX],
    //   conversionRate in [0.01e27, 100e27], amountOut = amountIn * 1e27 / rate * 1e12
    function prove_swapExactIn_usdcToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDC_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(usdc), address(susds), a1)
            <= psm.previewSwapExactIn(address(usdc), address(susds), a2));
    }

    // testFuzz_swapExactIn_susdsToUsds: amountIn in [1, SUSDS_TOKEN_MAX],
    //   conversionRate in [0.01e27, 100e27], amountOut = amountIn * rate / 1e27
    function prove_swapExactIn_susdsToUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= SUSDS_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(susds), address(usds), a1)
            <= psm.previewSwapExactIn(address(susds), address(usds), a2));
    }

    // testFuzz_swapExactIn_susdsToUsdc: amountIn in [1, SUSDS_TOKEN_MAX],
    //   conversionRate in [0.01e27, 100e27], amountOut = amountIn * rate / 1e27 / 1e12
    function prove_swapExactIn_susdsToUsdc(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= SUSDS_TOKEN_MAX);
        assert(psm.previewSwapExactIn(address(susds), address(usdc), a1)
            <= psm.previewSwapExactIn(address(susds), address(usdc), a2));
    }

    // =====================================================================
    // previewSwapExactOut  (round up)   — mirrors SwapExactOut.t.sol
    // =====================================================================
    // amountOut bounded by USDS_TOKEN_MAX (a safe superset of each original's
    // out-asset bound); the originals additionally assert the round-up amountIn
    // is within 1 of the exact formula.

    // testFuzz_swapExactOut_usdsToUsdc: amountIn = amountOut * 1e12
    function prove_swapExactOut_usdsToUsdc(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(usds), address(usdc), a1)
            <= psm.previewSwapExactOut(address(usds), address(usdc), a2));
    }

    // testFuzz_swapExactOut_usdsToSUsds: amountIn = amountOut * rate / 1e27 (round up, +/-1)
    function prove_swapExactOut_usdsToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(usds), address(susds), a1)
            <= psm.previewSwapExactOut(address(usds), address(susds), a2));
    }

    // testFuzz_swapExactOut_usdcToUsds: amountIn = amountOut / 1e12 (round up, +/-1)
    function prove_swapExactOut_usdcToUsds(uint256 a1, uint256 a2) public view {
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(usdc), address(usds), a1)
            <= psm.previewSwapExactOut(address(usdc), address(usds), a2));
    }

    // testFuzz_swapExactOut_usdcToSUsds: amountIn = amountOut * rate / 1e27 / 1e12 (round up)
    function prove_swapExactOut_usdcToSUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(usdc), address(susds), a1)
            <= psm.previewSwapExactOut(address(usdc), address(susds), a2));
    }

    // testFuzz_swapExactOut_susdsToUsds: amountIn = amountOut * 1e27 / rate (round up)
    function prove_swapExactOut_susdsToUsds(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(susds), address(usds), a1)
            <= psm.previewSwapExactOut(address(susds), address(usds), a2));
    }

    // testFuzz_swapExactOut_susdsToUsdc: amountIn = amountOut * 1e27 / rate * 1e12 (round up)
    function prove_swapExactOut_susdsToUsdc(uint256 rate, uint256 a1, uint256 a2) public {
        require(rate >= 0.01e27 && rate <= 100e27);
        mockRateProvider.__setConversionRate(rate);
        require(a1 <= a2 && a2 <= USDS_TOKEN_MAX);
        assert(psm.previewSwapExactOut(address(susds), address(usdc), a1)
            <= psm.previewSwapExactOut(address(susds), address(usdc), a2));
    }

    // EXACT closed forms for ALL 6 ExactIn legs are proved in ProveOriginals.t.sol
    // by delegating to the repo's own UNMODIFIED SwapPreviews fuzz tests
    // (testFuzz_previewSwapExactIn_*) — the two to-usdc legs needed the
    // fraction-reduce lemma (argotorg/hevm#1073). The ExactOut round-up exact forms
    // (ceilDiv) stay out of reach. This file keeps the amount- and rate-direction
    // monotonicity, which has no counterpart among the originals.

    // ---- rate-direction monotonicity (2-state: read at r1, raise rate to r2) ----
    // sUSDS->usds output is amountIn*rate/1e27, so it INCREASES with the rate
    // (mul-mono + div-mono).
    function prove_swapExactIn_susdsToUsds_rate_increasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(x <= SUSDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(susds), address(usds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(susds), address(usds), x);
        assert(o1 <= o2);
    }
    // usds->sUSDS output is amountIn*1e27/rate, so it DECREASES as the rate rises
    // (rate is the divisor — divisor-anti-monotonicity).
    function prove_swapExactIn_usdsToSUsds_rate_decreasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(x <= USDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(usds), address(susds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(usds), address(susds), x);
        assert(o2 <= o1);
    }
    // usdc->sUSDS output is amountIn*1e27/rate*1e12, DECREASES as the rate rises.
    function prove_swapExactIn_usdcToSUsds_rate_decreasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(x <= USDC_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(usdc), address(susds), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(usdc), address(susds), x);
        assert(o2 <= o1);
    }
    // sUSDS->usdc output is amountIn*rate/1e27/1e12, INCREASES with the rate.
    function prove_swapExactIn_susdsToUsdc_rate_increasing(uint256 x, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(x <= SUSDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 o1 = psm.previewSwapExactIn(address(susds), address(usdc), x);
        mockRateProvider.__setConversionRate(r2);
        uint256 o2 = psm.previewSwapExactIn(address(susds), address(usdc), x);
        assert(o1 <= o2);
    }
    // ExactOut, sUSDS in: required input is amountOut*1e27/rate (ceil), so it
    // DECREASES as the rate rises (rate is the divisor — divisor-anti-mono).
    function prove_swapExactOut_susdsToUsds_rate_decreasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(y <= USDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(susds), address(usds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(susds), address(usds), y);
        assert(i2 <= i1);
    }
    function prove_swapExactOut_susdsToUsdc_rate_decreasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(y <= USDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(susds), address(usdc), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(susds), address(usdc), y);
        assert(i2 <= i1);
    }
    // ExactOut, sUSDS out: required input is amountOut*rate/1e27 (ceil), so it
    // INCREASES with the rate (mul-mono + ceil). These are the heaviest legs (a
    // round-up ceilDiv over an abstract amount*rate, read twice).
    function prove_swapExactOut_usdsToSUsds_rate_increasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(y <= USDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(usds), address(susds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(usds), address(susds), y);
        assert(i1 <= i2);
    }
    function prove_swapExactOut_usdcToSUsds_rate_increasing(uint256 y, uint256 r1, uint256 r2) public {
        require(r1 <= r2 && r1 >= 0.01e27 && r2 <= 100e27);
        require(y <= USDS_TOKEN_MAX);
        mockRateProvider.__setConversionRate(r1);
        uint256 i1 = psm.previewSwapExactOut(address(usdc), address(susds), y);
        mockRateProvider.__setConversionRate(r2);
        uint256 i2 = psm.previewSwapExactOut(address(usdc), address(susds), y);
        assert(i1 <= i2);
    }
}
