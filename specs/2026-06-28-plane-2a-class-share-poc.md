# Plane-2a class-core eval-sharing — first PoC design (2026-06-28)

Goal: convert the synthetic-fleet harness's **0.96 content-shareability ceiling** into an
**actual measured eval-work saving**, intra-process, byte-identical-gated. This is the first
build step of the fleet-eval-sharing arm (after the step-2.0 substrate, 14/14, completed).

## The confirmed problem (measured, not hypothesised)

`synth-measure/lib.sh` over the synth fleet, forcing units drvPaths in ONE eval:

| host set (one eval) | copies | marginal |
|---------------------|--------|----------|
| base: axon-synth-001 | 28.96M | — |
| + 002 (SAME class, server-base) | 50.69M | **+21.73M = 75.0% of base** |
| + 007 (DIFFERENT class, agent)  | 50.68M | **+21.72M = 75.0% of base** |

**Same-class marginal == different-class marginal.** Nix's automatic thunk-memo captures only the
~25% nixpkgs/stdenv base; it shares **nothing class-specific**. Yet the parity oracle proves a
same-class host's core is **byte-identical** (224/225 units drvPath-equal). So 96 same-class
agents at N=100 recompute ~96 × 21.7M ≈ **2.1 billion copies of byte-identical core** — pure waste.
The upside of 2a = the class-invariant fraction of that 75%-per-host marginal.

(Root cause: each host is a separate `lib.nixosSystem` ⇒ separate `evalModules` fixpoint ⇒
separate thunks for the resolved config, even when the output drvPaths are equal. Confirms the
project_hola_perf C1-A0 finding "Nix memoises nothing across separate evalModules fixpoints" — and
shows the wasted work is large where the cores ARE shareable.)

## The mechanism — archetype-once + axis-injection (intra-process)

Exactly the spec's "force the archetype once, freeze a PLAIN projection, inject at
host.instantiate", realised at the units level for the PoC:

1. **Archetype.** Per class key, eval the CANONICALISED archetype once — the parity oracle's
   sentinel-axis config (`canonicalize.nix`). Its units map `archUnits` (the byte-identical core)
   is computed ONE time, as a plain value.
2. **Axis-dependent set.** Diff each real host's units against `archUnits` (the parity oracle's
   machinery) ⇒ the small AXIS-DEPENDENT key-set Δ(host) (the identity units: hostname, the eth0
   address, the per-host secret paths — ~1–2 units; 224/225 are in the shared core).
3. **Injection.** `hostUnits host = archUnits // (recompute ONLY Δ(host) for host)`. The shared
   core is the archetype thunk (computed once, reused free); only Δ(host) is paid per host.

**Soundness gate (already built):** the substitution `archUnits[k] == realHostUnits[k]` for the
shared keys is exactly what `parity-oracle.sh` asserts (canonicalised pair drvPath-equal). 2a is
applied ONLY to the keys the oracle certifies identical; Δ(host) is computed for real. The
planted-leak teeth-test guarantees an out-of-axis difference is NOT silently shared. So 2a is
sound-by-construction wherever the parity gate is green — and the gate is O(K) per class, not O(N).

## The measurement protocol (reuses the harness + lib.sh)

In ONE eval, compare two assemblies of N same-class hosts' units:

- **vanilla:** `deepSeq (map (h: realUnits h) hosts)` — copies = base + (N−1)·(75% marginal).
- **2a:** `deepSeq (archUnits :: map (h: deltaUnits h) hosts)` — copies = archetype-once +
  N·(Δ-only marginal).

Report (NIX_SHOW_STATS copies, deterministic, eval-cache off):
- `marginal_vanilla` (≈21.7M, measured) vs `marginal_2a` — **measured, not assumed.** `marginal_2a`
  is NOT "~1–2 units": forcing host h's Δ units still drags host h's full `systemd.units`
  module-merge spine (a separate fixpoint, the ~5.6% module-machinery class), paid in BOTH
  assemblies. So `marginal_2a` = (per-host module-merge spine) + (Δ-unit construction); the 2a
  saving is the shared ~224 units' **deep derivation construction** (the ~94% bulk, per
  project_hola_perf) lifted off the N-axis. Report the residual as measured; do not predict it.
- `saving(N) = copies_vanilla(N) − copies_2a(N)`, plotted vs N; the per-host saving →
  (shared-core deep-construction) once N ≫ 1 — the measured fraction of the 75% marginal that is
  class-invariant derivation construction, NOT the whole 75%.

Acceptance: `marginal_2a < marginal_vanilla` strictly and by a large factor; the 2a units set is
**drvPath-identical to vanilla** (no soundness loss — same parity hash); saving grows linearly in N.

## Honest bounds (stated, not hidden)

- **Intra-process only.** `archUnits` is shared within ONE eval (fleet flake-check / deploy-plan /
  CI). Across separate `nix eval` invocations it is recomputed ⇒ **2b** (cross-invocation
  persistence) needs the gen-rebuild content-addressed store keyed by the per-class selection hash
  — the net-new keystone, deferred.
- **Units proxy, not full toplevel.** The PoC shares the rendered UNITS; a full `toplevel` also has
  class-core + identity parts in /etc, activation, boot. Same principle, more surface; the units
  result is the lower bound on the win.
- **Production needs the den-hoag entrypoint.** Vanilla `nixosSystem` cannot be handed a
  pre-resolved class-core; assembling per-host toplevels from a shared archetype is precisely the
  "inject at host.instantiate" seam den-hoag owns (architecture spec §8a). The PoC demonstrates the
  saving; production wiring is the den-hoag integration.
- **drvPath equality = OUTPUT shareability**; the *eval-work* saving is the copies decomposition
  above. Stacks multiplicatively with Determinate parallel eval (≈3.7×, verbatim nixpkgs).

## Build order

1. `synth-measure/2a-share.sh` — archetype-once + Δ-injection assembly + the vanilla-vs-2a copies
   differential, gated by the parity hash (reject if any shared key is not drvPath-identical).
2. Sweep N {2,10,50,100} and K classes; report `saving(N)` + the per-host marginal collapse.
3. If green: write the measured saving into the baseline report; this is the first hard number for
   the fleet-eval-sharing arm. Then 2b (gen-rebuild persistence) and the den-hoag entrypoint.
