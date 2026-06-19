.PHONY: deploy
deploy-arbitrum-one :; forge script script/Deploy.s.sol:DeployArbitrumOne --sender ${ETH_FROM} --broadcast --verify
deploy-base 	    :; forge script script/Deploy.s.sol:DeployBase --sender ${ETH_FROM} --broadcast --verify
deploy-optimism	    :; forge script script/Deploy.s.sol:DeployOptimism --sender ${ETH_FROM} --broadcast --verify
deploy-unichain     :; forge script script/Deploy.s.sol:DeployUnichain --sender ${ETH_FROM} --broadcast --verify

# ---------------------------------------------------------------------------
# Symbolic verification of the PSM3 stateless proofs with echidna, using the
# arithmetic-abstraction hevm (argotorg/hevm#1073). Needs an abstraction-enabled
# echidna and bitwuzla on PATH. Config + target list: test/symbolic/echidna.yaml.
#
#   make verify          # verify every symbolic contract
#   make verify-real     # just the real-PSM3 proofs (ProveRealPSM3)
# ---------------------------------------------------------------------------
ECHIDNA         ?= echidna
SYMBOLIC_CONFIG := test/symbolic/echidna.yaml

# Every symbolic proof contract, as <file>:<contract>.
SYMBOLIC_CONTRACTS := \
	test/symbolic/ProveGetters.t.sol:ProveGetters \
	test/symbolic/ProveRounding.t.sol:ProveRounding \
	test/symbolic/ProveSwapPreviews.t.sol:ProveSwapPreviews \
	test/symbolic/ProveRealPSM3.t.sol:ProveRealPSM3 \
	test/symbolic/ProveOriginals.t.sol:ProveGettersOriginal \
	test/symbolic/ProveOriginals.t.sol:ProvePreviewDepositOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveSwapInUsdsOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveSwapInUsdcOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveSwapInSusdsOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToAssetsOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToAssetValueOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToSharesOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToSharesUsdsOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToSharesUsdcOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveConvertToSharesSusdsOriginal \
	test/symbolic/ProveOriginals.t.sol:ProveSwapOutUsdsOriginal

# echidna exits non-zero with workers:0 (only a symbolic worker), so `|| true`
# keeps the loop going; read the per-method "verified" lines for the result.
.PHONY: verify
verify:
	@for t in $(SYMBOLIC_CONTRACTS); do \
		file=$${t%%:*}; contract=$${t##*:}; \
		echo "=================================================================="; \
		echo " verifying $$contract  ($$file)"; \
		echo "=================================================================="; \
		$(ECHIDNA) $$file --contract $$contract --config $(SYMBOLIC_CONFIG) || true; \
	done

.PHONY: verify-real
verify-real:
	$(ECHIDNA) test/symbolic/ProveRealPSM3.t.sol --contract ProveRealPSM3 --config $(SYMBOLIC_CONFIG) || true
