// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";

import { MockRateProvider } from "test/mocks/MockRateProvider.sol";

import { PSM3 } from "src/PSM3.sol";

// Proves PSM3's stateless conversion properties against the REAL deployed
// contract: `psm` below is an actual `new PSM3(...)`, and every prove_ calls the
// real psm.* functions, so there is no copy of the conversion math to drift out
// of sync with src/PSM3.sol.
//
// The tokens and rate provider are minimal mocks whose `balanceOf` is a single
// storage slot (not a mapping). This is a NECESSARY modelling choice, not a
// shortcut: these properties run through the real totalAssets(), which reads the
// token balances. A real ERC20's mapping read is a giant keccak-indexed SMT term,
// and nested inside the abstracted nonlinear arithmetic it blows the query up
// past the solver's reach (verified: inheriting the real PSMTestBase/MockERC20,
// convertToAssetValue monotonicity returns `unknown` even at a 700s SMT timeout).
// The single-slot balance keeps the read a clean symbolic value while leaving
// PSM3 itself untouched. (The swap previews in ProveSwapPreviews.t.sol read no
// balances, so they DO reuse the real PSMTestBase/MockERC20.)
//
// The PSM holds symbolic balances of ALL THREE tokens, so totalAssets() is the
// real three-term sum (usdc * 1e12 + usds + susds * rate / 1e9 / 1e18);
// totalShares is written to its storage slot (2).
//
//   forge build --ast
//   hevm test --match "prove_" --abstract-arith --solver bitwuzla

// Drop-in for erc20-helpers MockERC20 with the SAME constructor and the same
// `mint` / `decimals` surface PSM3 and the fuzz tests use. The ONLY difference is
// that `balanceOf` is a single storage slot rather than a per-holder mapping:
// that keeps the balance read (which PSM3.totalAssets() performs) a clean
// symbolic value instead of a keccak-indexed mapping term, which is what
// otherwise puts the abstracted nonlinear query past the solver (see header).
// Single-holder is sound here: every property fixes the balances it depends on.
contract MockToken {
    string public name;
    string public symbol;
    uint8  public decimals;
    uint256 internal _bal;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_; symbol = symbol_; decimals = decimals_;
    }
    function balanceOf(address) external view returns (uint256) { return _bal; }
    function mint(address, uint256 amount_) external returns (bool) { _bal += amount_; return true; }
    function approve(address, uint256) external pure returns (bool) { return true; }
    function allowance(address, address) external pure returns (uint256) { return type(uint256).max; }
    // transfer/transferFrom are only exercised by setPocket's zero-amount move in
    // setUp; the proofs themselves call no transfers (only balanceOf reads), so a
    // success-returning no-op is sufficient and keeps the single balance slot.
    function transfer(address, uint256) external pure returns (bool) { return true; }
    function transferFrom(address, address, uint256) external pure returns (bool) { return true; }
}

contract ProveRealPSM3 is Test {

    uint256 constant TOTAL_SHARES_SLOT = 2;

    // Same names/types as PSMTestBase so the setup reads the same way.
    address public owner  = makeAddr("owner");
    address public pocket = makeAddr("pocket");

    PSM3      psm;
    MockToken usdc;
    MockToken usds;
    MockToken susds;
    MockRateProvider mockRateProvider;

    // Mirrors PSMTestBase.setUp(): same token names/decimals, the real
    // MockRateProvider at 1.25e27, the real `new PSM3(...)`, and setPocket.
    function setUp() public {
        usdc  = new MockToken("usdc",  "usdc",  6);
        usds  = new MockToken("usds",  "usds",  18);
        susds = new MockToken("susds", "susds", 18);

        mockRateProvider = new MockRateProvider();
        mockRateProvider.__setConversionRate(1.25e27);

        psm = new PSM3(owner, address(usdc), address(usds), address(susds), address(mockRateProvider));

        vm.prank(owner);
        psm.setPocket(pocket);
    }

    // Hold symbolic balances of all three tokens (=> totalAssets() is the real
    // sum) and set totalShares. The per-balance bound keeps the precision-scaling
    // multiplications inside totalAssets() from overflowing (which would just
    // revert); the conversion no-overflow is then bounded per property by
    // requiring totalAssets() < 2**128.
    function _setState(uint256 uc, uint256 ud, uint256 su, uint256 ts) internal {
        require(uc < 2**120 && ud < 2**120 && su < 2**120);
        usdc.mint(pocket,        uc);   // usdc custodian is the pocket
        usds.mint(address(psm),  ud);
        susds.mint(address(psm), su);
        vm.store(address(psm), bytes32(TOTAL_SHARES_SLOT), bytes32(ts));
    }

    // EXACT totalAssets() closed form (matches Getters.t.sol testFuzz_totalAssets),
    // against the real deployed PSM3 with single-slot symbolic balances and a
    // SYMBOLIC rate:  totalAssets() == usdc*1e12 + usds + susds*rate/1e27.
    // Each precision term is one lemma — usds: same-constant cancel (x*1e18/1e18);
    // usdc: generalized const-cancel (x*1e18/1e6, 1e6|1e18); susds:
    // nested-div-collapse (x*rate/1e9/1e18 == x*rate/1e27) — then summed linearly.
    // (Delegating to the original is intractable: the real MockERC20 mapping reads
    // blow the query up to `unknown`; single-slot balances keep it small.)
    function prove_totalAssets_exact(uint256 uc, uint256 ud, uint256 su, uint256 rate) public {
        require(rate >= 0.0001e27 && rate <= 1000e27);
        mockRateProvider.__setConversionRate(rate);
        _setState(uc, ud, su, 0);  // totalShares unused by totalAssets()
        uint256 r = mockRateProvider.getConversionRate();
        uint256 rhs;
        unchecked { rhs = uc * 1e12 + ud + su * r / 1e27; }
        assert(psm.totalAssets() == rhs);
    }

    // convertToAssetValue monotonic in numShares
    function prove_assetValue_monotonic(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s1, uint256 s2) public {
        _setState(uc, ud, su, ts);
        require(ts != 0);
        require(s1 <= s2 && s1 < 2**128 && s2 < 2**128);
        require(psm.totalAssets() < 2**128);
        assert(psm.convertToAssetValue(s1) <= psm.convertToAssetValue(s2));
    }

    // convertToShares monotonic in assetValue
    function prove_shares_monotonic(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 a1, uint256 a2) public {
        _setState(uc, ud, su, ts);
        require(psm.totalAssets() != 0);
        require(a1 <= a2 && a1 < 2**128 && a2 < 2**128 && ts < 2**128);
        assert(psm.convertToShares(a1) <= psm.convertToShares(a2));
    }

    // no share inflation: totalShares <= totalAssets => shares(value) <= value
    function prove_shares_no_inflation(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 v) public {
        _setState(uc, ud, su, ts);
        require(psm.totalAssets() != 0);
        require(ts <= psm.totalAssets());
        require(v < 2**128 && ts < 2**128 && psm.totalAssets() < 2**128);
        assert(psm.convertToShares(v) <= v);
    }

    // round trip: value -> shares -> value never creates value (inflation-attack safety)
    function prove_roundtrip_no_inflation(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 x) public {
        _setState(uc, ud, su, ts);
        require(ts != 0 && psm.totalAssets() != 0);
        require(x < 2**128 && ts < 2**128 && psm.totalAssets() < 2**128);
        assert(psm.convertToAssetValue(psm.convertToShares(x)) <= x);
    }

    // reverse round trip: shares -> value -> shares never creates shares
    function prove_roundtrip_shares(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s) public {
        _setState(uc, ud, su, ts);
        require(ts != 0 && psm.totalAssets() != 0);
        require(s < 2**128 && ts < 2**128 && psm.totalAssets() < 2**128);
        assert(psm.convertToShares(psm.convertToAssetValue(s)) <= s);
    }

    // convertToAssets(usdc, .) monotonic in numShares
    function prove_convertToAssets_usdc_monotonic(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s1, uint256 s2) public {
        _setState(uc, ud, su, ts);
        require(ts != 0);
        require(s1 <= s2 && s1 < 2**128 && s2 < 2**128);
        require(psm.totalAssets() < 2**128);
        assert(psm.convertToAssets(address(usdc), s1) <= psm.convertToAssets(address(usdc), s2));
    }

    // convertToAssets(susds, .) monotonic in numShares (at the deployed rate)
    function prove_convertToAssets_susds_monotonic(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s1, uint256 s2) public {
        _setState(uc, ud, su, ts);
        require(ts != 0);
        require(s1 <= s2 && s1 < 2**80 && s2 < 2**80);
        require(psm.totalAssets() < 2**80);
        assert(psm.convertToAssets(address(susds), s1) <= psm.convertToAssets(address(susds), s2));
    }

    // convertToAssetValue monotonic in totalAssets (backing increase, e.g. rate
    // move): read, raise the usds balance, read again — both on the real psm,
    // with the other two balances held symbolic.
    function prove_assetValue_backing_monotonic(uint256 uc, uint256 ud1, uint256 ud2, uint256 su, uint256 ts, uint256 s) public {
        require(ts != 0 && ud1 <= ud2 && s < 2**128);
        _setState(uc, ud1, su, ts);
        require(psm.totalAssets() < 2**128);
        uint256 v1 = psm.convertToAssetValue(s);
        require(ud2 < 2**120);
        usds.mint(address(psm), ud2 - ud1);  // additive: ud1 -> ud2
        require(psm.totalAssets() < 2**128);
        uint256 v2 = psm.convertToAssetValue(s);
        assert(v1 <= v2);
    }

    // convertToShares anti-monotonic in totalAssets: more backing => fewer shares per value
    function prove_shares_anti_monotonic_assets(uint256 uc, uint256 ud1, uint256 ud2, uint256 su, uint256 ts, uint256 v) public {
        require(ud1 <= ud2 && ts < 2**128 && v < 2**128);
        _setState(uc, ud1, su, ts);
        require(psm.totalAssets() != 0 && psm.totalAssets() < 2**128);
        uint256 q1 = psm.convertToShares(v);
        require(ud2 < 2**120);
        usds.mint(address(psm), ud2 - ud1);  // additive: ud1 -> ud2
        require(psm.totalAssets() < 2**128);
        uint256 q2 = psm.convertToShares(v);
        assert(q2 <= q1);
    }

    // EXACT-value lossless usds conversion (enabled by the const-cancellation
    // lemma): convertToAssets(usds, s) == convertToAssetValue(s). usds is 1:1, so
    // convertToAssets computes convertToAssetValue(s) * 1e18 / 1e18 — const-cancel
    // collapses the *1e18/1e18 wrapper, giving an exact equality (no rounding
    // loss for usds), which monotonicity alone could never establish.
    function prove_convertToAssets_usds_eq_value(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s) public {
        _setState(uc, ud, su, ts);
        require(ts != 0 && s < 2**128 && psm.totalAssets() < 2**128);
        assert(psm.convertToAssets(address(usds), s) == psm.convertToAssetValue(s));
    }

    // --- previewDeposit: first-deposit branch (no balances => totalAssets()==0,
    // so convertToShares returns the asset value directly and there is no
    // division by totalAssets). previewDeposit == getAssetValue here.
    function prove_pd_usds_firstdeposit_mono(uint256 x1, uint256 x2) public view {
        require(x1 <= x2 && x2 < 2**120);
        assert(psm.previewDeposit(address(usds), x1) <= psm.previewDeposit(address(usds), x2));
    }
    function prove_pd_usdc_firstdeposit_mono(uint256 x1, uint256 x2) public view {
        require(x1 <= x2 && x2 < 2**80);
        assert(psm.previewDeposit(address(usdc), x1) <= psm.previewDeposit(address(usdc), x2));
    }
    function prove_pd_susds_firstdeposit_mono(uint256 x1, uint256 x2) public view {
        require(x1 <= x2 && x2 < 2**60);
        assert(psm.previewDeposit(address(susds), x1) <= psm.previewDeposit(address(susds), x2));
    }
    // The EXACT-value first-deposit closed forms (previewDeposit(usds) == x,
    // (usdc) == x*1e12, (susds) == x*rate/1e27) are proved in ProveOriginals.t.sol
    // by delegating to the repo's own UNMODIFIED PreviewDeposit fuzz tests
    // (testFuzz_previewDeposit_*_firstDeposit) — no hand-rewritten copy here. The
    // monotonicity above has no original to delegate to, so it stays.
    //
    // NOTE: the GENERAL branch (totalAssets()!=0) of previewDeposit is NOT
    // provable — even monotonicity returns unknown (302s timeout, verified on the
    // fresh binary with all lemmas). There convertToShares divides by the symbolic
    // totalAssets() (av*ts/ta), and the abstraction's pairwise lemmas over that
    // nested structure explode; the const-cancel/nested-div lemmas only collapse
    // constant factors, not the symbolic ts/ta division. The first-deposit exacts
    // above prove precisely because that branch returns the value with no such
    // division. See CANDIDATES.md "previewDeposit investigation".
}
