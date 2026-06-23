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
