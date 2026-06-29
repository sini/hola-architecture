# Plane-2a PoC — Task-0 baseline + go/no-go (2026-06-28)

Task-0 of `plans/2026-06-28-plane-2a-class-share-poc.md`. Establishes the class, the
shared/delta unit split, the per-key laziness gate, and the decisive marginal — **GO**.

## The class

At N=100 the largest same-class group = **96 hosts** (`axon-synth-004 … 099`, channel
`nixos-unstable`, x86_64-linux, 12 includes — the *agent* class; the 0.96 exact-share ceiling).
At N=10 the same class is 6 hosts (`004 … 009`). `archHost = axon-synth-004`.
(`001/002` are a separate size-2 class — the parity-oracle's HA/HB.)

## Shared / delta split (the soundness boundary)

`sharedKeys` = unit keys **present on every member AND drvPath-identical across all**; `deltaKeys`
= the rest. Measured (N=10, shared facter, all 6 members): **total 240 units, sharedKeys = 212,
delta = 28** (per-host ~225 units; the union is 240 because of per-host-unique keys). Δ = the
per-host identity units: `acme-<hostname>.*` service/timer/target (per-host-UNIQUE keys),
`persist-…` machine-id mounts, `frr.service`, `nftables.service`, `systemd-networkd.service`,
plus the hostname-embedding `dbus-broker.service` / `polkit.service` / `tailscaled*.service`.
`nftables.service ∈ deltaKeys` ✓ (the reviewer's natural-teeth check — the documented out-of-axis
residual lands in Δ by construction, never silently shared).

### Facter-regime finding (shapes the measurement)

Under the **default `varied` facter regime**, a single host pair under-discovers Δ: 004/005 agreed
on `dbus/polkit/tailscaled` but **006 diverged** on them. The byte-identical class core is the
parity-oracle's premise, which `canonicalize.nix` obtains by pinning facter to the canonical value.
So the PoC uses **`facterRegime=shared`** (the homogeneous class — matches the real byte-identical
class axon-02/03 and the oracle). `varied` is a separate, smaller-core bound (harness already has
the T8b facter-diff). Even under `shared`, `dbus/polkit/tailscaled` are in Δ because they embed the
per-host **hostname** (the entity key, sentinelized only by `canonicalize.nix` at the nixos level) —
correctly isolated to Δ, not a soundness problem.

## Per-key laziness micro-check (Reviewer Fix #1 — the load-bearing gate)

Forcing ONE unit vs the FULL 228-unit map on one host at N=100: **one unit = 128.0M copies, full =
141.0M**. Reading one unit already drags ~91% of the cost — because the per-host module-merge spine
(+ the N=100 fleet-resolution base, paid once) dominates; the units' marginal deep-construction is
only ~13M. This looked alarming in isolation, but it is exactly the liftable quantity: see the
marginal below. **The laziness holds** (forcing Δ-only skips the shared-units construction).

## The decisive marginal (N=10, shared facter, removeAttrs assembly)

| assembly | M=2 copies | M=6 copies | **marginal / host** |
|---|---|---|---|
| vanilla `deepSeq (map realUnits hosts)` | 50,690,140 | 137,578,820 | **21.72M** |
| 2a `deepSeq ([arch] ++ map (h: arch // removeAttrs (realUnits h) sharedKeys) hosts)` | 37,726,916 | 72,762,336 | **8.76M** |

- `vanilla M=2 = 50.69M` reproduces the PoC-spec table exactly (validates the measurement).
- **marginal collapses 21.72M → 8.76M / host (≈60% reduction); `saving ≈ 12.96M copies/host`,
  linear in N** (saving(2)=12.96M, saving(6)=64.82M ⇒ +12.96M/host).
- The lifted ~12.96M = the 212 class-invariant units' deep derivation construction (≈ the micro-
  check's 13M); the **residual 8.76M/host = the per-host `systemd.units` module-merge spine**, a
  separate `nixosSystem` fixpoint 2a cannot lift intra-process (Gate-B's stated WHNF bound, paid in
  BOTH assemblies). Honest decomposition, not a fake win.
- Extrapolated: at the full 96-host class, ≈ 96 × 12.96M ≈ **1.24 billion copies avoided** per fleet
  eval (same order as the spec's ~2.1B total-recompute estimate; the ~40% residual = the spine).

## Soundness (byte-identical gate)

`(arch // removeAttrs (realUnits "axon-synth-005") sharedKeys)` vs `realUnits "axon-synth-005"`:
**`identical = true`**, both 225 keys (per-key drvPath JSON equal). The 2a assembly reconstructs the
real host's units map exactly — the saving is byte-identical-gated, zero soundness loss.

## Implementation notes for `2a-share.sh` (Task 1)

1. **`removeAttrs (realUnits h) sharedKeys`** is the right per-host delta (NOT `genAttrs deltaKeys`):
   it handles per-host-UNIQUE keys (each host's own `acme-<hostname>` units) and makes the identity
   check exact by construction. Assembly: `arch // removeAttrs (realUnits h) sharedKeys`.
2. **Splice unit-key names with `json.dumps(k)`**, NOT `f'"{k}"'` — systemd unit names contain
   backslash escapes (`persist-persist-etc-machine\x2did.service`); a raw splice drops the `\` and
   throws `attribute missing`. `json.dumps` emits a valid Nix string literal (escapes `\` and `"`).
3. `archUnits = mk sharedKeys (k: (realUnits archHost).${k})` forced once; `mk = ks: f:
   builtins.listToAttrs (map (k: { name = k; value = f k; }) ks)` (pure builtins — no `lib.*`).
4. Each eval ends in ONE selected expression (vanilla XOR twoA), bash-spliced M-host list — not an
   attrset-of-lambdas.
5. `facterRegime=shared`; `sharedKeys` computed present-in-all-AND-identical over the sweep members;
   **zero-exclusion parity gate** across all sweep hosts + assert `nftables.service ∈ deltaKeys`.
6. Eval contract: `bash` (not zsh — `${BASH_SOURCE[0]}`), `cd "$SYNTH_ROOT"` before `.#` evals,
   never wrap a shell function in `timeout`. lib.sh daemon path works (no hang).

## Verdict: GO

Real, sound, byte-identical-gated ~60% per-host marginal collapse on the 96-host class. Proceed to
Task 1 (productionize `2a-share.sh` with the parity gate + N{2,10,50,100} × ≥2-class sweep).
