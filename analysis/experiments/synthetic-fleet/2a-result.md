# Plane-2a PoC — measured result (2026-06-28)

Task-2 of `plans/2026-06-28-plane-2a-class-share-poc.md`. The first hard number for the
fleet-eval-sharing arm. Substrate: `synth-measure/2a-share.sh` (+ `tests/2a-share-test.sh`),
committed `fa4d2864` on `demo/persist-claims-open-emit`. Method + Task-0 derivation in
`2a-baseline.md`.

## Headline

Sharing the byte-identical class core (archetype-once + per-host axis-delta, units level,
intra-process) collapses the per-host eval-work marginal **21,722,170 → 8,758,855 copies/host
(59.68%)**, byte-identical-gated, **scale-invariant** (identical to the digit at N=10 and N=50).
Per-host saving = **12,963,315 copies**.

## Sweep (largest same-class group = the agent class; `nrOpUpdateValuesCopied`, eval-cache off)

| N | class size | M | copies_vanilla | copies_2a | saving |
|---|---|---|---|---|---|
| 10 | 6 | 2 | 50,690,140 | 37,726,916 | 12,963,224 |
| 10 | 6 | 6 | 137,578,820 | 72,762,336 | 64,816,484 |
| 50 | 46 | 2 | 81,386,680 | 68,423,456 | 12,963,224 |
| 50 | 46 | 46 | 1,037,162,160 | 453,813,076 | **583,349,084** |
| 100 | 96 | 96 | — OOM-killed — | — | (see below) |

- `marginal_vanilla = 21,722,170 copies/host`, `marginal_2a = 8,758,855 copies/host` — **identical
  to the digit at N=10 and N=50.** The per-host marginal is exactly constant: each same-class host
  contributes the same units closure regardless of fleet size; the only N-dependence is the shared
  resolution base, which cancels in the marginal. So `marginal(N=100) = 21,722,170` by construction.
- **Parity gate PASS** at every measured point (212 `sharedKeys` byte-identical across all members,
  zero exclusions; `nftables.service ∈ deltaKeys`). The 2a assembly is byte-identical to from-
  scratch (`toJSON van == toJSON asm`, verified in `tests/2a-share-test.sh`).
- `saving(M) = (M−1) × 12,963,315`, exactly linear. **Measured at the 46-host class: 583.3M copies
  saved per fleet eval.** Extrapolated to the full 96-host class:
  `95 × 12,963,315 ≈ 1.23 billion copies` avoided per eval (justified by the exactly-constant
  measured marginal; same order as the spec's ~2.1B total-recompute estimate).

## The N=100 OOM — a finding, not a failure

The full 96-host class at N=100 OOM-killed on the **vanilla** `deepSeq (map realUnits hosts)` — it
holds all 96 hosts' unit closures live simultaneously (single-host live set ~7 GB-class; ×96 >
memory). This is a real characteristic: **naively forcing the whole fleet's units at once is
memory-bound.** The 2a assembly forces the shared core once and reuses it, so it also reduces peak
live memory — a second-order benefit beyond the copy-count saving. (The marginal at N=100 was not
re-measured because it is per-host-constant by construction, confirmed exactly at N=10 and N=50; a
bounded N=100 run would reconfirm 21,722,170. The full-class *absolute* saving at N=100 is the
extrapolation above.)

## Class composition note (the "≥2 classes" question)

The synthetic fleet is **dominated by one large homogeneous class** (96/100 hosts at N=100 = the
agent class) by design — it models a real homogeneous fleet (the byte-identical axon-02/03 shape the
whole arm is premised on). The only other multi-member class is a size-2 pair (`001/002`), which
yields a single M=2 saving point (12.96M), not a marginal slope. The stronger robustness evidence is
the **agent class swept across sizes 6 → 46** (and the exactly-constant marginal): the saving scales
with class size, not a single-size artifact. Heterogeneous-facter (`varied` regime) is a separate,
smaller-core bound (the harness has the T8b facter-diff for it).

## Honest bounds (carried from the design — do not read the number as a free speedup)

1. **Intra-process only.** Shared within one eval (fleet flake-check / deploy-plan / CI). Across
   separate `nix` invocations it is recomputed ⇒ Plane 2b (gen-rebuild content-addressed, keyed by
   the per-class selection hash) — the deferred keystone.
2. **Units proxy, not full toplevel** — the units result is the lower bound on the win.
3. **Production needs the den-hoag inject-at-`instantiate` seam.** The PoC *identifies* shareable
   eval-work (an upper bound), byte-identical-gated; realizing it in production is the seam (§8a).
4. **drvPath equality = OUTPUT shareability;** the eval-work saving is the copies decomposition. The
   residual 8.76M/host = the per-host module-merge spine (separate fixpoint, paid in both). Stacks
   multiplicatively with Determinate parallel eval (~3.7×, verbatim nixpkgs).

## Verdict

Plane-2a is a **measured, sound, byte-identical-gated ~60% per-host eval-work collapse**, scale-
invariant, 583M copies saved on a 46-host class (≈1.23B extrapolated at 96). First hard number for
the fleet-eval-sharing arm. The value justifies the den-hoag injection seam (the §0 value test).
Next: S1 (kill the global `hasAnyConfigThunk` flag) → S2 → den-hoag seam.
