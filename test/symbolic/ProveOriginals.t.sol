// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { PSMHarnessTests }               from "test/unit/Getters.t.sol";
import { PSMPreviewDeposit_SuccessTests } from "test/unit/PreviewDeposit.t.sol";
import {
    PSMPreviewSwapExactIn_UsdsAssetInTests,
    PSMPreviewSwapExactIn_USDCAssetInTests,
    PSMPreviewSwapExactIn_SUsdsAssetInTests,
    PSMPreviewSwapExactOut_UsdsAssetInTests
} from "test/unit/SwapPreviews.t.sol";
import {
    PSMConvertToAssetsTests,
    PSMConvertToAssetValueTests,
    PSMConvertToSharesTests,
    PSMConvertToSharesWithUsdsTests,
    PSMConvertToSharesWithUsdcTests,
    PSMConvertToSharesWithSUsdsTests
} from "test/unit/Conversions.t.sol";

// Prove the repo's UNMODIFIED stateless fuzz tests symbolically.
//
// Each prove_ inherits the real test contract and delegates to its testFuzz_*, so
// the property — and its exact closed form, asserted with forge-std assertEq — is
// the original, not a copy. The only addition is a require() supplying the
// multiplication abstraction's operand bound; it lands inside forge-std _bound's
// early-return window, so the wrap-around modulo in the original is unreachable and
// never enters the query.
//
// Bounds mirror each original's _bound range. Where that range exceeds the
// abstraction's 2**128 operand budget (the getUsd* fuzz uses 1e45) the proven
// domain is the 2**128 subset — still far above any real supply.
//
//   hevm test --match "prove_" --abstract-arith --solver bitwuzla

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

// totalAssets() exact is NOT delegated here: through the real MockERC20 (a mapping
// balanceOf per token) the query is intractable, even though the arithmetic is a
// linear sum of three lemma-discharged terms. Its tractable home is ProveRealPSM3
// (single-slot balances), as prove_totalAssets_exact.

// no-value / first-branch closed forms: totalShares == 0, so the conversions return
// the asset value with no share division. Delegated from Conversions.t.sol.

contract ProveConvertToAssetsOriginal is PSMConvertToAssetsTests {
    function prove_convertToAssets_usdc(uint256 amount) public view {   // (usds,x) == x
        require(amount <= USDS_TOKEN_MAX);
        testFuzz_convertToAssets_usdc(amount);
    }
    function prove_convertToAssets_usds(uint256 amount) public view {   // (usdc,x) == x/1e12, fraction-reduce
        require(amount <= USDC_TOKEN_MAX);
        testFuzz_convertToAssets_usds(amount);
    }
    function prove_convertToAssets_susds(uint256 rate, uint256 amount) public {  // (susds,x) == x*1e27/rate
        require(rate >= 0.0001e27 && rate <= 1000e27);
        require(amount <= SUSDS_TOKEN_MAX);
        testFuzz_convertToAssets_susds(rate, amount);
    }
}

contract ProveConvertToAssetValueOriginal is PSMConvertToAssetValueTests {
    function prove_convertToAssetValue_noValue(uint256 amount) public view {  // == x (identity)
        testFuzz_convertToAssetValue_noValue(amount);
    }
}

contract ProveConvertToSharesOriginal is PSMConvertToSharesTests {
    function prove_convertToShares_noValue(uint256 amount) public view {  // == x (identity)
        testFuzz_convertToShares_noValue(amount);
    }
}

contract ProveConvertToSharesUsdsOriginal is PSMConvertToSharesWithUsdsTests {
    function prove_convertToShares_usds_noValue(uint256 amount) public view {  // (usds,x) == x
        require(amount <= USDS_TOKEN_MAX);
        testFuzz_convertToShares_noValue(amount);
    }
}

contract ProveConvertToSharesUsdcOriginal is PSMConvertToSharesWithUsdcTests {
    function prove_convertToShares_usdc_noValue(uint256 amount) public view {  // (usdc,x) == x*1e12, gen const-cancel
        require(amount <= USDC_TOKEN_MAX);
        testFuzz_convertToShares_noValue(amount);
    }
}

contract ProveConvertToSharesSusdsOriginal is PSMConvertToSharesWithSUsdsTests {
    function prove_convertToShares_susds_noValue(uint256 amount, uint256 rate) public {  // (susds,x) == x*rate/1e27
        require(amount >= 1000 && amount <= SUSDS_TOKEN_MAX);
        require(rate >= 0.01e27 && rate <= 1000e27);
        testFuzz_convertToShares_noValue(amount, rate);
    }
}

// previewSwapExactOut rounds the input UP (Math.ceilDiv). The ceilDiv-cancel lemma
// discharges the one leg whose product is exactly divisible — usds->usdc:
// ceilDiv(amountOut*1e18, 1e6) == amountOut*1e12 (1e6 | 1e18, so ceil == floor).
// The other legs round over a non-divisible / rate-based ceilDiv, out of reach as an
// exact form; ProveSwapPreviews proves their monotonicity instead.
contract ProveSwapOutUsdsOriginal is PSMPreviewSwapExactOut_UsdsAssetInTests {
    function prove_previewSwapExactOut_usdsToUsdc(uint256 amountOut) public view {  // == amountOut*1e12
        require(amountOut <= USDC_TOKEN_MAX);
        testFuzz_previewSwapExactOut_usdsToUsdc(amountOut);
    }
}
