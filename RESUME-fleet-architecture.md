# RESUME — Fleet Eval-Sharing & Distributed Queries (current frontier, 2026-06-25)

State dump before history compaction. Companion to memory `project_hola.md` (dense record) + the spec below (authoritative).

## Where we are
Designed + gate-validated a **den-hoag × hola × gen fleet architecture**. All three gates GREEN on real axon. The bolt-on E3c-C1 approach is dead (negative record); this declared-boundary, den-hoag-entrypoint design replaces it.

## Authoritative artifacts
- **Architecture spec (THE doc, UNCOMMITTED):** `specs/2026-06-25-fleet-eval-sharing-architecture.md`. Sections: §0 value test, §1 the one idea, §2 evidence, §3 axon class, §4 query (Tier-1 baseline / Tier-2 open), §5 class-core sharing (Gate-B proven), §6 incremental, §7 soundness, §8 roles + §8a seam S1–S4 + §8b worked persist-claims example, §9 perf, §10 staging (gates green + build order), §11 open decisions, §12 refs.
- **Negative record (COMMITTED, papers main 8a18a1f/3202f0b/d570ef2):** `specs/2026-06-24-hola-e3c-c1-cross-scope-sharing-design.md` — per-host *discovered*-boundary sharing = net-negative (C1-A0 NO-GO). Do NOT re-chase.
- **Engine substrate (SHIPPED, github:sini/hola @de5b21d):** E1/E2a/E2b byte-identical evalModules ownership + parity harness.

## THE VALUE TEST (north star — user, sharp)
Closed (entity-record) emits need NONE of this — independently evaluable, den does them today (claim/provide = pipe.collect over closed quirks). **The entire value = make the OPEN emit (config-dependent cross-host relations: host A reads host B's RESOLVED config) affordable at fleet scale** — the capability den ships but nix-config keeps DORMANT (reading peer config across the fleet was the blow-up). Judge every mechanism by: does it aid the open emit?

## Architecture in one breath
The open emit reads peer `config.X`. Three mechanisms make that read cheap+shared: **per-edge laziness** (Gate A — scoped open emit already forces only matched peers, TODAY), **cone-expander S2** (`pipe.reads [cone]` → read only the declared cone, not full peer config), **class-sharing Plane 2** (if the cone is class-invariant, resolve once per class). N-fold faster fleet *build* = side benefit of the same sharing. Role split: den-hoag = flake entrypoint + declared decomposition; gen = primitives (scope/graph/rebuild/derive); hola = per-node nixpkgs hosting + byte-identical parity gate.

## Gate results (workflow wh0ygg53t — all GREEN)
- **Gate A (boundary): pass-constrained.** 11/11 real cross-host emits pipeline-parametric (closed); 2 config-dep emits are LOCAL age-secrets. Per-edge scoping already inherent via Nix laziness (`/tmp/d5_lazy_probe.nix`: config-dep collect from axon-02 forces axon-02 ALONE). Global `hasAnyConfigThunk` = latent footgun (S1 kills it).
- **Gate B (Plane 2a): 2a-REAL-WIN — with a stated bound.** Eval-WORK shared (CORE-FORCED=1 vs reconstruct=2) on real axon-02/03, byte-identical (`a02-core→a03 system.path == a03`, `z81p0vvk…`), via mkForce class-invariant projection through `nixosSystem.extendModules` — a faithful **MODEL** of the den-hoag closed-injection-at-instantiate seam (`host.nix:397`); **the real `host.instantiate` wiring is S3, UNBUILT.** **BOUND (do not over-read `REAL-DEF-FORCED=0`):** the shared thing is the **deep construction (drvPath) behind WHNF**; the real def is STILL WHNF-touched per member — `mergeDefinitions` (`modules.nix:1185+`) property-discharges every def (`isAttrs v && v ? _type`) to WHNF before `filterOverrides` drops the loser. So per-member residual = (WHNF-discharge of shared defs = cost-center-A merge) + aggregation roots + ~43 leaves; only the deep construction is lifted off the N-axis. Proven on ONE projection (system.path) — **the summed per-member residual must be confirmed against the full core** before claiming the N-fold.
- **Plane 1: works at zero force** (200-host query = 0 toplevels) — but this is the *closed/Tier-1 baseline* (§0), not the value.
- **Demand (the 4th gate): VALIDATED — config-based cross-host eval is a HARD NEED**, not a nice-to-have. Currently worked around in nix-config because the open emit forces fleet-wide eval. **Target bar = "ideally FREE."** This is the north-star the whole arm is a GO against; do NOT re-litigate or shelve it.

## Empirical evidence (probes — /tmp may be cleared; conclusions are durable here + in spec §12)
- `/tmp/hola_homogeneous.nix` — class-sharing 2-vs-N (synthetic).
- `/tmp/wf_thread_probe.nix` — defs-append shares valueBase forced ONCE across keys; per-key distinct args.
- `/tmp/hola_c2_cost.nix` — sound per-host-sentinel C2 = 4 vs 3 (net-negative — why heterogeneous discovered-boundary fails).
- `/tmp/hola_c1a0_realdiff.nix` — real axon-style diff; `/tmp/hola_tier2.nix` — real axon uids (acme=976…) class-invariant across axon-02/03 (deterministic-uids); `/tmp/hola_typed_vs_lazy.nix` — non-forcing channel soundness boundary (typed attrsOf safe, lazyAttrsOf/raw unsafe); `/tmp/hola_presence.nix`, `/tmp/hola_selfcatch.nix`, `/tmp/wf_union_unsound.nix` — the throws-NOT-observed unsound subclass.
- Grounding workflows: `weqp366dj` (axon/den/gen grounding), `wh0ygg53t` (gates). Outputs under the session tasks dir (ephemeral; conclusions in spec/memory).

## Axon class facts (the real fixtures)
- Clean class {axon-02, axon-03} (byte-identical ~13-aspect includes, `axon-0N.nix:48-63`). **axon-01 = SUPERCLASS** (+`services.storage.media-scratch`, `axon-01.nix:60`). **Class key = sorted `den.aspects.<host>.includes`** (NOT hostname).
- Per-host axis = ~7-field record (hostname; ipv4/ipv6 `host.nix:258-283`; tb-loopback+nsap `:378-386`; 2 disk device_ids; facter.json `:392`; agenix secrets `:391`; all `identity=false`).
- 94–95% (den-layer) of the derivation-construction cost-center is host-invariant.

## den seam facts (for S1–S4 / D5)
- Boundary: `isConfigDependent = isFunction val && (functionArgs val) ? config` (`resolve.nix:392`). Closed emit `{host,environment,...}`, open `{host,config,...}`.
- Pipe API (`policy-effects.nix:296-346`): `pipe.from name [filter/transform/fold/append/for/withProvenance/to/as/expose/collect/collectAll]`. Real emit shape: `k3s.nix:48` `k3s-nodes = { environment, host, ... }: { ... host.name ... }`. Collect policies: `modules/den/policies/pipes.nix` (`pipe.from "k3s-nodes" [ (pipe.collect ({host,...}: true)) ]`).
- `hasAnyConfigThunk` global all-or-nothing `resolve.nix:393-408` → `hostConfigs` lazy mapAttrs `:468`; `markConfigThunk` deferred-local `class-module.nix:157-168`; `spawnNode` hostConfigs=null `spawn-node.nix:115`. quirk decls `modules/den/quirks/<name>.nix`.
- `pipe.reads [paths]` (S2) = PROPOSED new verb (not shipped). claim/provide = pipe.collect aggregation (NO separate "claim engine"/"connect kind 0" in code — papers only).
- gen: `gen-rebuild` threads gen-scope but NEVER consumes it (the 2b keystone is net-new; `FUTURE_WORK.md`). `flakeOutputs.nix:42-46` = today only nixosConfigurations (need `flake.den.hosts` for live-flake Plane 1).

## Build order (re-centered on the open emit; spec §10)
1. ✅ **DONE 2026-06-26 — Unlock the open emit on real axon.** Wired the first real open cross-host quirk (`persist-claims` reading peer `config.users.users.frr.uid`=978, scoped `pipe.collect`, rides `services.bgp.spoke`) on a throwaway nix-config branch in a worktree; measured on real axon-02. **All 3 claims PASS** (evidence `analysis/experiments/fleet-open-emit/`, papers main 7ebf82f; branch `demo/persist-claims-open-emit`@bc6a0cb7 NEVER merged, patch captured): M1 capability (3-entry axon-class result, scoped-bound structurally visible); M2 scoped-bounded (A=3.97×B copies ≈3 not 7 hosts, zero peer toplevels forced, fn only 1.37×=baseline thunk-memoized); M3 cheap (open read=8.3% of toplevel COPIES, derivation-construction 91.7% avoided). **CONFIRMED first open emit in nix-config** (all existing emits read entity record only ⇒ dormant). **Gate-B bound made concrete: COPIES discriminates, fn-calls don't** (reading any option forces ~whole module-merge/cost-center-A; only derivation-construction copies avoided). frr is the read because it's the only host-level declarative svc uid on the axon class (k8s=pods, media=axon-01-only).
2. **Seam S2/S1 (NEXT)** — `pipe.reads` cone-expander + unscoped-collectAll+config-dep lint + kill global flag. **DEN-FRAMEWORK change** ⇒ den branch + `--override-input den` + a nix-config quirk consuming it (the build-into-den + input-swap pattern, in its correct place).
3. **Plane 2a class-share** — extend Gate-B to full class-invariant cone; class-key partition; per-class O(K) byte-identical parity gate (mandatory for non-forcing channels — force-count = throws-OBSERVED only).
4. **Plane 3 incremental** — gen-rebuild override (data) / applyEdgeDelta+re-partition (topology).
5. **Plane 2b keystone (deferred)** — gen-rebuild consume gen-scope = cross-invocation persistence.

## SETTLED vs PENDING
- **SETTLED (do not re-open):** the arm is a **GO** — demand validated (open emit = hard need, target ideally-free), all gates green. Closed/Tier-1 is the solved baseline, not the value (§0).
- **PENDING = next ACTION only** (not the GO): **(a) build the real-axon open-emit demonstration** (persist-claim collector, scoped, measured — first artifact exercising actual value), **(b) writing-plans** (staged build), or **(c) commit the architecture spec**. Recommendation: **(a)** — exercises the open emit on the real fleet and sizes what S2+class-sharing buy at 100 hosts.

## The "ideally free" asymptote (calibrate against the bar; don't overpromise)
- **S2 cone-expander:** kills the blow-up — `O(N×toplevel)` → `O(peers×cone)`. Buildable.
- **2a class-sharing (intra-process):** ~**free per-host for class-invariant reads** (the common case — deterministic uids/ports). Buildable; Gate-B-proven (with the §Gate-B bound).
- **"Free in the dev loop" (cross-invocation):** = **2b, UNBUILT and hard** (gen-rebuild threads gen-scope but never consumes it). Do NOT promise dev-loop-free off S2+2a — that's 2b.

## Open decisions (spec §11; mostly resolved)
D1 class-key lifecycle (where sorted(includes) computed; axon-01 superclass vs overlay); D2 projection (Gate B used system.path drvPath — works); D3 2b substrate; D4 gate placement + re-validation trigger (member-config change forces O(K) re-validate, never affected-set-pruned); D5 = the seam §8a (RESOLVED — remaining: pipe.reads API surface + ship S1 standalone?); D6 first-cut scope (axon-only recommended).

## Commit status
- papers `main`: e3c spec (8a18a1f, 3202f0b, d570ef2); **fleet architecture spec + RESUME COMMITTED 279d4cd**; step-1 demo spec 90ee065; step-1 evidence 7ebf82f. All pushed.
- **Code:** step-1 demo lives on throwaway nix-config branch `demo/persist-claims-open-emit`@bc6a0cb7 (worktree `nix-config/.worktrees/persist-claims-open-emit`, off main 384297df, NEVER merged); patch in `analysis/experiments/fleet-open-emit/persist-claims-demo.patch`. den + nix-config main UNCHANGED. Worktree still present (offer cleanup).
