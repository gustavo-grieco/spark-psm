// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.13;

import { Test } from "forge-std/Test.sol";

import { MockRateProvider } from "test/mocks/MockRateProvider.sol";

import { PSM3 } from "src/PSM3.sol";

// Proves PSM3's stateless conversion properties against the REAL deployed PSM3
// (psm is an actual new PSM3(...)), so the conversion math can't drift from src.
//
// The tokens use a single-slot balanceOf rather than a per-holder mapping — a
// modelling necessity, not a shortcut. These properties run through the real
// totalAssets(), which reads token balances; a mapping read is a keccak-indexed SMT
// term that, nested inside the abstracted nonlinear arithmetic, puts the query past
// the solver. A single-slot balance keeps the read a clean symbolic value while
// leaving PSM3 untouched. (The swap previews read no balances, so they reuse the
// real MockERC20.)
//
// Most properties here are MONOTONICITY / round-trip rather than the exact share
// formula (which needs the symbolic totalShares/totalAssets division, out of the
// abstraction's reach). That fallback is useful, not a consolation: monotonicity IS
// the safety property — a non-monotonic conversion lets a user split or reorder
// amounts to extract value, and a round-trip returning more than it took is an
// inflation attack — so proving them rules out those exploit classes directly.
// Where the exact value is reachable (usds is 1:1) we prove that too.
//
//   hevm test --match "prove_" --abstract-arith --solver bitwuzla

// Drop-in MockERC20 with the same surface PSM3 uses, except balanceOf is a single
// storage slot, not a per-holder mapping (see header). Single-holder is sound here:
// every property fixes the balances it depends on.
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
    // Only setPocket's zero-amount move calls these in setUp; the proofs read only
    // balanceOf, so a no-op suffices.
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

    // Hold symbolic balances of all three tokens (=> totalAssets() is the real sum)
    // and set totalShares. The per-balance bound keeps the precision multiplies from
    // overflowing; per property, conversion no-overflow is bounded via
    // totalAssets() < 2**128.
    function _setState(uint256 uc, uint256 ud, uint256 su, uint256 ts) internal {
        require(uc < 2**120 && ud < 2**120 && su < 2**120);
        usdc.mint(pocket,        uc);   // usdc custodian is the pocket
        usds.mint(address(psm),  ud);
        susds.mint(address(psm), su);
        vm.store(address(psm), bytes32(TOTAL_SHARES_SLOT), bytes32(ts));
    }

    // EXACT totalAssets() closed form (matches Getters.t.sol testFuzz_totalAssets)
    // against the real PSM3 with symbolic balances and a symbolic rate:
    // usdc*1e12 + usds + susds*rate/1e27. One lemma per precision term — usds:
    // same-constant cancel (x*1e18/1e18); usdc: const-cancel (x*1e18/1e6); susds:
    // nested-div-collapse (x*rate/1e9/1e18 == x*rate/1e27) — summed linearly.
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

    // EXACT lossless usds conversion (const-cancel lemma): usds is 1:1, so
    // convertToAssets computes convertToAssetValue(s)*1e18/1e18; const-cancel
    // collapses the wrapper to an exact equality — no rounding loss, a guarantee
    // beyond what monotonicity alone could give.
    function prove_convertToAssets_usds_eq_value(uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 s) public {
        _setState(uc, ud, su, ts);
        require(ts != 0 && s < 2**128 && psm.totalAssets() < 2**128);
        assert(psm.convertToAssets(address(usds), s) == psm.convertToAssetValue(s));
    }

    // EXACT share-supply invariance — the core of the conversionRateIncrease fuzz
    // tests (Conversions.t.sol): the pool's whole current value always converts back
    // to exactly the total share supply, at any balances and any rate. convertToShares
    // computes totalAssets()*totalShares/totalAssets(), which the cancellation lemma
    // ((a*b)/a == b) collapses to totalShares — so revaluing the pool (a rate change)
    // moves the dollar value but never dilutes or inflates the share count. EXACT, the
    // strongest form, not just monotone.
    function prove_convertToShares_totalValue_eq_totalShares(
        uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 rate
    ) public {
        require(rate >= 0.0001e27 && rate <= 1000e27);
        mockRateProvider.__setConversionRate(rate);
        _setState(uc, ud, su, ts);
        require(psm.totalAssets() != 0 && psm.totalAssets() < 2**128 && ts < 2**128);
        assert(psm.convertToShares(psm.totalAssets()) == psm.totalShares());
    }

    // Dual identity, and the core of the convertToAssetValue conversionRate fuzz
    // tests: all shares always convert back to exactly the pool's whole value, at any
    // rate. convertToAssetValue computes totalShares*totalAssets()/totalShares, which
    // the cancellation lemma collapses to totalAssets(). With the identity above this
    // is the exact aggregate share<->value bijection — the two convert*(expectedShares)
    // == value assertions in every conversionRate test reduce to these. (The tests'
    // third line — the value CHANGE equals susds*(rate-1e27)/1e27 — relates two
    // distinct abstract products and needs a distributivity lemma the abstraction
    // does not yet have, so it is not covered here.)
    function prove_convertToAssetValue_totalShares_eq_totalAssets(
        uint256 uc, uint256 ud, uint256 su, uint256 ts, uint256 rate
    ) public {
        require(rate >= 0.0001e27 && rate <= 1000e27);
        mockRateProvider.__setConversionRate(rate);
        _setState(uc, ud, su, ts);
        require(psm.totalShares() != 0 && psm.totalAssets() < 2**128 && ts < 2**128);
        assert(psm.convertToAssetValue(psm.totalShares()) == psm.totalAssets());
    }

    // Third assertion of the conversionRate fuzz tests: when the rate rises from
    // 1e27 to q, totalAssets() rises by EXACTLY the sUSDS revaluation,
    // su*(q-1e27)/1e27 (the usdc/usds legs are rate-independent and cancel). This is
    // the value-change accounting line, against the real totalAssets() read twice.
    // Discharged by the scaled-product telescoping lemma (argotorg/hevm#1073):
    // su*q/1e27 - su*1e27/1e27 == su*(q-1e27)/1e27, relating the two abstract
    // products su*q and su*(q-1e27).
    function prove_totalAssets_rateIncrease_valueChange(
        uint256 uc, uint256 ud, uint256 su, uint256 q
    ) public {
        require(q >= 1e27 && q <= 1000e27);
        _setState(uc, ud, su, 0);
        mockRateProvider.__setConversionRate(1e27);
        uint256 v1 = psm.totalAssets();
        mockRateProvider.__setConversionRate(q);
        uint256 v2 = psm.totalAssets();
        require(v2 < 2**128);
        assert(v2 - v1 == su * (q - 1e27) / 1e27);
    }

    // previewDeposit first-deposit branch: no balances => totalAssets()==0, so
    // convertToShares returns the asset value with no division (previewDeposit ==
    // getAssetValue). Exact closed forms (usds==x, usdc==x*1e12, susds==x*rate/1e27)
    // are delegated in ProveOriginals; the monotonicity here — more deposited never
    // mints fewer shares — has no original to delegate to, so it stays.
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
    // The GENERAL branch (totalAssets()!=0) is out of reach even for monotonicity:
    // there convertToShares divides by the symbolic totalAssets() (av*ts/ta), and the
    // abstraction's lemmas collapse only constant factors, not that symbolic division.
}
