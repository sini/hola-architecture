# hola — Resume Prompt (design & planning, next phase)

> Paste this into a fresh session to pick up **design + planning** for hola.
> Pairs with the auto-memories `project_hola` and `project_zen_vic` (already in
> `~/.claude/memory/`). Caveman/compressed prose was used this session; match the
> user's density. Dated 2026-06-23.

## Who/what

You are picking up **hola** — a proposed **pure-gen / graph-paradigm** Nix module
engine that hosts *unmodified* nixpkgs/NixOS modules. Its value is **sound
incremental override** (den's documented context-threading pain), **correctness**
(located cycles, no-throw accumulating blame, inspectable composition), and
**external lazy module selection** — judged against **zen** (the effects-paradigm
sibling, Vic's) on incrementality / complexity / correctness / parity, **not** on
wall-time. It is built foundation-first: a new gen library, **`gen-rebuild`** (the
Mokhov *rebuilder*), then the engine on top.

## Where we are (roadmap)

- **Phase 0 Research ✅** — evaluated adios/adios-flake + zen; profiled cortex (the
  pivot); reframed hola to graph-paradigm + non-perf value.
- **Phase 1 Theory ✅** — acquired the 3 canonical rebuilder papers; finalized the
  ~18-op `gen-rebuild` surface.
- **Phase 2a Spec ✅** — `gen-rebuild` design spec, reviewed twice (original +
  fresh-eyes), approved.
- **Phase 2b Plan ✅** — v1 implementation plan (Tasks 0–5, TDD) + `.tasks.json`.
- **Phase 2b EXECUTION (in flight)** — building the new repo
  `~/Documents/repos/gen-rebuild/` in a **parallel session** via `executing-plans`.
  Per `.tasks.json`: **Tasks 0–3 done** (scaffold, build+store+cycle-precheck,
  affected, dirtySet), **Task 4 in_progress** (`override` + seeded soundness
  property test — the thesis), **Task 5 pending** (the B demo).

## The next phase = YOUR job

1. **Verify v1 finished** — check `gen-rebuild` Tasks 4 & 5 landed green
   (`cd ~/Documents/repos/gen-rebuild/ci && nix flake check`; the B demo at
   `examples/dag`).
2. **Phase 3 — the paradigm GO/NO-GO (the B demo, Task 5).** Does graph-based
   incremental override (a) work *soundly* (override-store == from-scratch over the
   seeded property test) and (b) read *cleaner* than zen's effects version? This is
   the decision the whole pivot rests on. Review it honestly; if it doesn't beat
   effects on clarity/incrementality, that's a real finding.
3. **If GO — design + plan the next increment.** The fork (decide with the user):
   - **`gen-rebuild` v2** — complete the rebuilder domain: rebuilder strategies
     (`verify`/`constructive`/`deepConstructive`/`earlyCutoff`/`needsEval`),
     provenance (`support`/`why`), drivers (`demand`/`applyDelta`/`batch`/
     `propagate`/`retract`), `restabilize`; + land the generic seams (gen-scope
     **S1** warm-cache, **S2** dep-record, **S6** order-stamp; gen-graph **S3**
     frontier, **S4** seeded fixpoint). v3 later = intra-eval optimality
     (characteristic-graph `O(|AFFECTED|)` + the sharing/swapping/switching triple).
   - **hola Phase 4 — the engine on nixpkgs.** Parity harness (dual-run vs
     `lib.evalModules`) + a minimal **hosted-`lib.types`-merge** engine that **owns
     `modules.nix`** for the submodule shape-hoist (lib.extend is bypassed for
     submodules — verified) + **external lazy module selection** from the HOAG graph.
   - Recommendation when you get there: lean **v2 first** (complete the foundation
     the engine consumes) unless the B demo makes a compelling case to prove the
     engine-on-nixpkgs path sooner.

## Load-bearing decisions & constraints (do NOT relitigate without cause)

- **Pure-gen / GRAPH, not effects.** zen is reference/comparator only — derive
  convergences (located cycles, blame, mk* priority) from graph principles, don't
  port zen's effect implementation.
- **PURE-ONLY.** The impure cross-eval "external shell" (amortized `dirty`/`gc`/
  persisted-mutable-trace = cheap cross-edit eval cache) is **out of scope** — a
  different *stateful* substrate, not a deferred hola component. Pure gen-rebuild =
  the complete pure-Nix rebuilder (Mokhov scheduler⟂rebuilder; the *revalidation*
  half rides Nix laziness free; only *invalidation* amortization needs impurity,
  H6). Cross-eval *result* reuse is the Nix store (deep-constructive via IFD), but
  build-cost-shaped. Detail: `den-ag-design/gen-specs/gen-rebuild/2026-06-23-pure-core-external-shell-analysis.md`.
- **Host `lib.types` merge VERBATIM** (don't reimplement the merge kernel — it's
  mutually recursive with evalModules, value-shape-dispatched, positional, throws).
  Own only the outer shape + a scalar priority pre-pass.
- **Own `modules.nix`** for the per-host submodule shape-hoist (the only clean
  per-host machinery win); `lib.extend` reaches only the root level.
- **External lazy module selection** from the HOAG graph is the differentiator
  (vs PR #148456, which needed per-module hand-annotation).
- **cortex's ~50s is intrinsic** (derivation construction, GC-bound on ~235M
  copies) — NOT a module-system problem. That perf belongs to the **evaluator
  layer** (Lix / Determinate parallel-eval), a **deferred, separate track**, never
  a hola daemon. Profile: `hola-architecture/analysis/experiments/cortex-profile/`.
- **Constraints to obey** (full text in the docs): per-host engine constraints
  **K1–K9** + verified claims **H1–H7** (`phase-2-implementation-seed.md`,
  `phase-1-feasibility.md`). H1 = the // copy-storm floor (~1.756M copies just to
  import nixpkgs) — untouchable. H6 = no cross-process persistence in pure Nix.

## References (exact)

| What | Where |
|---|---|
| Project home (research, surface, roadmap) | `~/Documents/papers/hola-architecture/` (github.com/sini/hola-architecture, **private**) |
| — Phase 1 (H1–H7) | `analysis/phase-1-feasibility.md` |
| — Phase 2 seed (K1–K9, engine constraints) | `analysis/phase-2-implementation-seed.md` |
| — gen-rebuild surface (~18 ops, seams S1–S9) | `analysis/gen-rebuild-surface.md` |
| — overall roadmap | `PLAN.md` |
| — evidence (cortex profile, workflow JSONs, fixtures) | `analysis/experiments/` |
| gen-rebuild spec + analysis + plan | `~/Documents/papers/den-architecture/gen-specs/gen-rebuild/` (github.com/sini/den-ag-design) — `2026-06-23-gen-rebuild-design.md`, `…-pure-core-external-shell-analysis.md`, `…-v1-plan.md` (+ `.tasks.json`) |
| theory papers (pdf/markdown/summaries) | `den-ag-design/reference-catalog/` + `used/summaries/` — Mokhov-2018, Forgy-1982, Radul-2009, Arntzenius-2016, Acar-2002, Hammer-2014 (Adapton), Reps-1983 (RTD), Vogt/Hedin (AG), etc. |
| **gen-rebuild code (being built)** | `~/Documents/repos/gen-rebuild/` (github:sini/gen-rebuild) |
| gen ecosystem deps | `~/Documents/repos/{gen-graph,gen-scope,gen,gen-derive,gen-schema,gen-aspects,gen-algebra,...}` |
| zen (reference, Vic's) | `~/Documents/repos/zen` (github:denful/zen) — effects/streams: bend/ned/nix-effects |
| adios / adios-flake / nixpkgs | `~/Documents/repos/{adios,adios-flake,nixpkgs}` |
| nix-config (integration target) | `~/Documents/repos/sini/nix-config` (colmena fork, dendritic; cortex host) |
| Gists (secret) | gen-rebuild=`a686008496b48d184fdd4caf2ea88089` (spec+analysis+plan); PLAN=`89cf2832516d44203d17fc78fdd8a3a3`; Phase-2 seed=`f72ca2fa777335892a112bbf81f5b8b5`; Phase-1=`669baadfe4af2f6b3211e5fdd31c00c9` |
| Memory | `~/.claude/memory/{project_hola,project_zen_vic}.md` |

## How we work (methodology)

- **Research** → multi-agent **Workflow** (ultracode): parallel source-grounded
  readers → synthesis → **adversarial 3-lens verification** of load-bearing claims.
  All claims grounded in real source (file:line), measured with `NIX_SHOW_STATS`.
- **Design** → brainstorming skill → **writing-plans** (bite-sized TDD tasks) →
  **executing-plans** in a parallel session. **Fresh-eyes review loops** on every
  spec/plan (they keep catching real bugs — use them).
- **gen principle:** each lib is a **complete, faithful** implementation of the ONE
  theory domain it cites. Run **gen-theory-conformance** at each lib gate.
- **Honesty discipline:** report findings straight (the cortex pivot, refuted
  claims). Don't let an exciting reframe inflate confidence past the evidence.

## Standing preferences / gotchas

- **Specs/plans → papers repos** (`~/Documents/papers/<proj>-architecture/`),
  **never** `docs/superpowers/`.
- **No native CC `TaskCreate`** during plan execution — the `pre-commit-check-tasks`
  hook blocks all commits while tasks are incomplete. Use plan checkboxes +
  `.tasks.json`.
- **`gh gist edit` is sandbox-blocked** (group-ID error). To update a gist in place
  use `gh api -X PATCH /gists/<id> --input -` with a `jq -n --rawfile … '{files:…}'`
  payload. (`gh gist create` works; the classifier may block private-derived
  content — if so, hand the user a `! gh …` command.)
- **Commits:** no Co-Authored-By, no bylines; stage specific files (never `-A`);
  format before committing.
- **nix-config:** `~/Documents/repos/sini/nix-config` (NOT `~/Documents/repos/nix-config`).
- **Date:** convert relative dates to absolute when recording.

## First action for the resuming session

Check whether `gen-rebuild` v1 finished (Tasks 4 + 5 green, B demo evaluates).
Then bring the **B-demo result** to the user as the Phase-3 go/no-go, and propose
the next-increment fork (v2 vs hola Phase 4) — with a recommendation, not a survey.
