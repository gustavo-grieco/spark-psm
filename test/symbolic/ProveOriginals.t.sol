// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMHarnessTests }               from "test/unit/Getters.t.sol";
import { PSMPreviewDeposit_SuccessTests } from "test/unit/PreviewDeposit.t.sol";
import {
    PSMPreviewSwapExactIn_UsdsAssetInTests,
    PSMPreviewSwapExactIn_USDCAssetInTests,
    PSMPreviewSwapExactIn_SUsdsAssetInTests
} from "test/unit/SwapPreviews.t.sol";

// Prove the UNMODIFIED stateless fuzz tests symbolically.
//
// Each `prove_` below inherits the repo's real test contract and DELEGATES to its
// `testFuzz_*` function — the property logic (and its forge-std `assertEq` exact
// closed form) is the original, not a copy, so there is nothing to drift. The only
// thing added is the `require(...)` that supplies the multiplication abstraction's
// operand bound. That `require` also lands inside forge-std `_bound`'s early-return
// window (`_bound` returns its argument unchanged when already in [min,max]), so
// the wrap-around modulo inside the original is on an infeasible branch and never
// enters the SMT query. (Verified: hevm implements the `assertEq` cheatcode and
// branches on symbolic operands — a false delegate is caught as a counterexample,
// not vacuously passed.)
//
// Bounds mirror each original's `_bound` range so the early-return fires; where the
// original's range exceeds the abstraction's 2**128 operand budget (the getUsd*
// fuzz uses 1e45) the proven domain is the 2**128 subset — still far above any real
// supply. Only the legs the abstraction's cancellation lemmas reach are delegated:
// the two legs converting TO usdc (`x/1e12`, a fraction-reduce) and every ExactOut
// round-up leg (a ceilDiv over an abstract product) stay `unknown`, so they are not
// included here (their monotonicity lives in ProveSwapPreviews.t.sol).
//
//   forge build --ast
//   hevm test --root . --match "prove_" --abstract-arith --solver bitwuzla \
//        --max-iterations 50 --smt-timeout 300

contract ProveGettersOriginal is PSMHarnessTests {
    function prove_getUsdsValue(uint256 x) public view {
        require(x < 2**128);                         // orig _bound(.,0,1e45); 2**128 subset
        testFuzz_getUsdsValue(x);
    }
    function prove_getUsdcValue(uint256 x) public view {
        require(x < 2**128);                         // orig _bound(.,0,1e45); 2**128 subset
        testFuzz_getUsdcValue(x);
    }
    function prove_getSUsdsValue(uint256 rate, uint256 amount) public {
        require(rate <= 1000e27 && amount <= SUSDS_TOKEN_MAX);
        testFuzz_getSUsdsValue_roundDown(rate, amount);
    }
    function prove_getAssetValue(uint256 amount) public view {
        require(amount <= SUSDS_TOKEN_MAX);
        testFuzz_getAssetValue(amount);
    }
}

contract ProvePreviewDepositOriginal is PSMPreviewDeposit_SuccessTests {
    function prove_previewDeposit_usds_firstDeposit(uint256 x) public view {
        require(x <= USDS_TOKEN_MAX);
        testFuzz_previewDeposit_usds_firstDeposit(x);
    }
    function prove_previewDeposit_usdc_firstDeposit(uint256 x) public view {
        require(x <= USDC_TOKEN_MAX);
        testFuzz_previewDeposit_usdc_firstDeposit(x);
    }
    function prove_previewDeposit_susds_firstDeposit(uint256 x) public view {
        require(x <= SUSDS_TOKEN_MAX);
        testFuzz_previewDeposit_susds_firstDeposit(x);
    }
}

contract ProveSwapInUsdsOriginal is PSMPreviewSwapExactIn_UsdsAssetInTests {
    function prove_previewSwapExactIn_usdsToUsdc(uint256 amountIn) public view {
        require(amountIn <= USDS_TOKEN_MAX);                 // == amountIn/1e12; fraction-reduce
        testFuzz_previewSwapExactIn_usdsToUsdc(amountIn);
    }
    function prove_previewSwapExactIn_usdsToSUsds(uint256 amountIn, uint256 rate) public {
        require(amountIn >= 1 && amountIn <= USDS_TOKEN_MAX);
        require(rate >= 0.0001e27 && rate <= 1000e27);
        testFuzz_previewSwapExactIn_usdsToSUsds(amountIn, rate);
    }
}

contract ProveSwapInUsdcOriginal is PSMPreviewSwapExactIn_USDCAssetInTests {
    function prove_previewSwapExactIn_usdcToUsds(uint256 amountIn) public view {
        require(amountIn <= USDC_TOKEN_MAX);
        testFuzz_previewSwapExactIn_usdcToUsds(amountIn);
    }
    function prove_previewSwapExactIn_usdcToSUsds(uint256 amountIn, uint256 rate) public {
        require(amountIn >= 1 && amountIn <= USDC_TOKEN_MAX);
        require(rate >= 0.0001e27 && rate <= 1000e27);
        testFuzz_previewSwapExactIn_usdcToSUsds(amountIn, rate);
    }
}

contract ProveSwapInSusdsOriginal is PSMPreviewSwapExactIn_SUsdsAssetInTests {
    function prove_previewSwapExactIn_susdsToUsds(uint256 amountIn, uint256 rate) public {
        require(amountIn >= 1 && amountIn <= SUSDS_TOKEN_MAX);
        require(rate >= 0.0001e27 && rate <= 1000e27);
        testFuzz_previewSwapExactIn_susdsToUsds(amountIn, rate);
    }
    function prove_previewSwapExactIn_susdsToUsdc(uint256 amountIn, uint256 rate) public {
        require(amountIn >= 1 && amountIn <= SUSDS_TOKEN_MAX); // == x*rate/1e27/1e12
        require(rate >= 0.0001e27 && rate <= 1000e27);         // nested-collapse + fraction-reduce
        testFuzz_previewSwapExactIn_susdsToUsdc(amountIn, rate);
    }
}

// NOTE: totalAssets() exact (== usds + usdc*1e12 + susds*rate/1e27, the repo's
// testFuzz_totalAssets) is NOT delegated here. Delegating runs it through the real
// MockERC20 (mapping balanceOf for three tokens), which returns `unknown` at a
// 302s timeout even though the arithmetic is just a linear sum of three
// lemma-discharged terms. Its tractable home is ProveRealPSM3 (single-slot mock
// balances), as prove_totalAssets_exact.
