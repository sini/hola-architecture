# hola — Overall Plan (rough draft)

**Status:** roadmap, 2026-06-23. High-level phase goals + gates — task-level plans
come per-phase (one spec → plan → implement cycle per buildable unit). See
`analysis/` for the research this rests on.

## Thesis (post-pivot)

hola is the pure-gen / **graph**-paradigm module engine. Its value is **sound
incremental override** (den's documented context-threading pain), **correctness**
(located cycles, no-throw accumulating blame), **inspectable composition**, and
**external lazy module selection**. It is built by first completing a new gen
library — the **rebuilder** (`gen-rebuild`) — then realizing the engine on it.

It is judged against **zen** (the effects-paradigm sibling) on
*incrementality / complexity / correctness / parity* — **not** on wall-time. The
cortex profile established that single-host eval is ~94% intrinsic derivation
construction (an evaluator-layer problem, deferred to Lix/parallel-eval), so
"faster than `lib.evalModules` on real configs" is explicitly **not** a headline
claim. (See `analysis/experiments/cortex-profile/`.)

**Perf re-pivot (2026-06-24, measured on cortex):** the ~50s is intrinsic, *but*
**cross-scope eval-result sharing is the one pure-Nix perf lever** — the redundancy of
N scopes (home-manager *users*, fleet *hosts*) re-evaluating identical module
subtrees, which Determinate's parallel eval *parallelizes* but does not *dedupe*. That
is the new **Phase 4.5 track** below. (Adopting Determinate is the separate
evaluator-layer track; the two compose.)

---

## Phase 0 — Research & reframe ✅ DONE

Phase 1/2 feasibility, cortex profile → the pivot, reframe to graph + non-perf
value, `gen-rebuild` identified as the foundation. All committed under
`analysis/` (`phase-1-feasibility.md`, `phase-2-implementation-seed.md`,
`experiments/`, the workflow result JSONs).

## Phase 1 — Theory completion ← **next**

- Acquire **Acar (self-adjusting computation / change propagation)** +
  **Hammer et al. (Adapton)** + **Reps–Teitelbaum–Demers (incremental attribute
  evaluation)** into the reference-catalog (summaries).
- Re-derive the **final ~15-op `gen-rebuild` surface** — adds `dirty`/`clean` and
  `gc` (Adapton), formally grounds the splice (Acar) and `dirtySet` minimality
  (Reps–Teitelbaum–Demers).
- **Gate:** a complete, theory-faithful operation surface + seam list (S1–S5).

## Phase 2 — Build `gen-rebuild` (the gen extension, first)

The rebuilder is the *incremental/self-adjusting* dimension of Mokhov 2018,
factored out of the *scheduler* (gen-scope) and the *topology oracle* (gen-graph).
A complete, single-domain gen library, useful beyond hola.

- **2a — Spec:** store shape (flat, relocatable, id-keyed), the op surface, the
  gen-scope/gen-graph seams. Spec-review loop.
- **2b — Seams:** land minimal, generic seams in gen-scope (**S1** warm-cache eval,
  **S2** dep-recording) + gen-graph (**S3** frontier `dependents`, **S4** seeded
  fixpoint), each with its own tests; do not break the shipped libs.
- **2c — Implement:** minimal subset first (`override` + `dirtySet` + `affected`),
  then the complete domain (rebuilder strategies, deltas, provenance,
  `restabilize`). TDD.
- **2d — Conformance:** gen-theory-conformance pass — faithful vs overclaim vs the
  cited papers.
- **Gate:** `gen-rebuild` is a complete, conformant, standalone gen lib
  (independent of hola and nixpkgs).

### `gen-rebuild` operation surface (target ~15 ops, 4+ theory clusters)

| Cluster | Ops | Theory |
|---|---|---|
| Core | `override` | Mokhov dirty-bit + Acar SAC; splice = delta-nets sharing |
| Rebuilder strategies | `verify` · `constructive` · `deepConstructive` · `earlyCutoff` | Mokhov §4.2 + §2.3 |
| Deltas | `applyDelta` · `batch` · `retract` · `dirtySet` | Forgy/Rete · Radul retraction |
| Provenance | `support` · `why` · `affected` | Radul §6.1 · Arntzenius reverse-reach |
| Incremental fixpoint | `restabilize` | Arntzenius semi-naive warm-start |
| (from Phase 1 papers) | `dirty`/`clean` · `gc` | Adapton |

**Boundary:** gen-scope = *scheduler* ("compute K now"); gen-rebuild = *rebuilder*
("must we, given last time?"); gen-graph = *topology oracle*. Conflict
negotiation / reconciliation stay **out** (the merge layer — gen-derive or a
future truth-maintenance lib), keeping gen-rebuild a faithful single-domain lib.

## Phase 3 — B: the thesis demo (validation + docs-as-code)

- **Abstract value-DAG** examples → pure-form docs-as-code: sound incremental
  override + located cycles, side-by-side with zen's effects version.
- **den cross-host** (synthetic) example → integration-shaped.
- **Gate (the paradigm go/no-go):** override recomputes *exactly* the reverse cone
  (trace proof); result == full re-eval (soundness); located cycles (no-throw). If
  the graph doesn't beat effects on clarity/incrementality here, stop — *before*
  the heavy Phase-4 compat engineering.

## Phase 4 — A: realize hola (engine on nixpkgs)

- Parity harness (dual-run vs `lib.evalModules`) + a minimal
  **hosted-`lib.types`-merge** engine that owns the `modules.nix` shape (per the
  Phase-2 seed doc, constraints K1–K9).
- Wire: gen-scope (HOAG composition) + gen-rebuild (incremental layer) + external
  lazy module selection.
- **Gate:** byte-identical `system.build.toplevel.drvPath` on a real host;
  incremental override works on real (unmodified) nixpkgs modules; complexity /
  parity compared to zen.

## Phase 5 — nix-config integration (the real test)

- den cross-host discovery on the real fleet; sound incremental override across
  hosts.
- **Bounded by H6:** cross-edit incrementality (across `nix eval` invocations)
  needs a **persistent eval server** — see deferred tracks.

## Phase 4.5 — Cross-scope eval-result sharing (the overlay-dedupe track)

**Lever:** N scopes — home-manager *users*, fleet *hosts* — re-evaluate identical
module subtrees from scratch. This is the one **pure-Nix** perf lever from the
re-pivot: the redundancy Determinate's parallel eval *parallelizes* but never
*dedupes*. Measured on cortex: home-manager (3 users) = ~46% of the eval (108M copies
/ 2.7 GB / 15s), atop a separate `useGlobalPkgs=false` 3×-nixpkgs amplifier.

**Zen premise corrected (verified vs zen source):** zen does **not** share evaluated
results across scopes. Its 3–10× byte-identical is a *single-config* zen-vs-`lib.evalModules`
result (intra-eval, from not paying `lib.evalModules`'s ~61k-primop base);
"submodule-as-scope" = no recursive fixpoint per *nested* submodule **within one
config**; its fleet-demo calls `lib.nixosSystem` once per host (fresh eval each). So
cross-scope *result* sharing is genuinely **unbuilt** — even in zen. The mechanism
that supplies it is **gen-rebuild's content-addressed memoized reuse**
(`build`/`override`/`affectedSet`), hosted by the engine owning the `evalModules`
call-site. (Zen's intra-config win is also *not* portable into verbatim
`lib.evalModules` — it requires replacing the evaluator, i.e. the Phase-4 bet — and
carries an O(N²) located-cycle term to avoid inheriting.)

**Two layers (keep separate):**
- **L1 — pkgs/overlay (config, no hola):** `useGlobalPkgs=false`
  (`den/core/users/home-manager.nix`) makes each user re-`import nixpkgs`.
  `useGlobalPkgs=true` collapses 3 → 1 in stock Nix — cheapest first win, but a **real
  migration** (per-user overlays like fenix must move to a shared overlay; drvPaths
  shift — measure, don't assume invariance).
- **L2 — module-eval (the hola lever):** the HM module set is re-evaluated per user
  regardless of pkgs. Seam: `home-manager/nixos/common.nix:26,142` —
  `users = attrsOf (submoduleWith …)` runs one `lib.evalModules` **per user, zero
  cross-key memo**. Injecting a pre-evaluated shared base + merging per-user deltas is
  **impossible in stock Nix**; it needs **owning the evalModules call-site**
  (`extendModules`-style base+delta) = the engine + gen-rebuild reuse.

**Cortex prototype (proving ground — earlier/smaller than the Phase-5 fleet):** one
machine, one heap, 3 scopes, gateable with the existing parity harness. Measured
shared/delta: `will`=15 pkgs (pure roles.default base), `shuo`=18 (base+3),
`sini`=275 (heavy delta) — 2/3 users ~95% shareable, `sini` mostly delta (win real but
**bounded**). **Gate = 4 byte-identical drvPaths:** system `toplevel` (master) +
per-user `home.activationPackage.drvPath`; baseline `NIX_SHOW_STATS` → apply → re-eval
identical → compare nrThunks/wall/heap.

**Milestones:**
- **C0 (now, no hola):** L1 — `useGlobalPkgs=true` + reconcile overlays; measure the
  pkgs-collapse; record the (deliberately shifted) new baseline. Independent of Phase 4.
- **C1 (needs the engine, Phase 4):** L2 — evaluate the shared roles.default HM subtree
  once, share across users via gen-rebuild reuse; gate byte-identical; measure dedupe.
- **C2 (Phase 5):** generalize — N hosts has the *same* shape (`nixosSystem` per host ≡
  `attrsOf submoduleWith` per user); L2 lifts to cross-host. Stacks on the Determinate
  track (parallel eval × dedup compose).

**Bound (honest):** capped by what's actually invariant across scopes (high
`will`/`shuo`, low `sini`); L1 (pkgs) is the bigger immediate chunk but config-fixable;
L2 (module-eval) is the novel hola contribution but bounded. **Deps:** gen-rebuild reuse
(Phase 2) + engine owning evalModules + parity gate (Phase 4); C0 independent.

---

## Deferred / separate tracks (decoupled, not blocking)

- **cortex's ~50s eval** → Lix / Determinate parallel-eval (evaluator layer; keeps
  `lib.evalModules` verbatim; ~no new code). The actual fix for that number.
- **Eval server** (out-of-language persistence) → unlocks Phase-5 cross-edit
  incrementality. Pure Nix cannot persist a forced thunk across invocations (H6).

## Cross-cutting

- **Parity harness** = the continuous correctness gate from Phase 4 on.
- **zen** = the standing comparison axis (incrementality / complexity / correctness
  / parity); not a benchmark in this phase.
- **Theory-conformance** at every gen-lib gate.
- **Artifacts/specs** → this papers repo; one spec → plan → implement cycle per
  buildable unit.

## Critical path & risk

- **Critical path = Phase 2 (`gen-rebuild`)** — a real, complete library in its own
  right.
- **Phase 3 (B) is the real go/no-go** — the paradigm earns its keep vs zen there,
  cheaply, before Phase-4 compat engineering.
