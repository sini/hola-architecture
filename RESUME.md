# hola — Resume Prompt (Phase 4: the engine on nixpkgs)

> Paste this into a fresh session to pick up **hola Phase 4 increment 2 — the
> engine arm**. Pairs with the auto-memories `project_hola` and `project_zen_vic`
> (already in `~/.claude/memory/`). Caveman/compressed prose was used these
> sessions; match the user's density. Dated 2026-06-24.
>
> **NOTE (handoff):** this prompt's **hola side** is current. The **gen-rebuild
> side** (v2 final-review outcome, exact main SHA / test count) is being finalized
> by the parallel gen-rebuild agent right after this edit — trust that agent's
> update for the gen-rebuild status line, and confirm `gen-rebuild` main is green
> before consuming it.

## Who/what

You are picking up **hola** — a proposed **pure-gen / graph-paradigm** Nix module
engine that hosts *unmodified* nixpkgs/NixOS modules. Its value is **sound
incremental override** (den's documented context-threading pain), **correctness**
(located cycles, no-throw accumulating blame, inspectable composition), and
**external lazy module selection** — judged against **zen** (the effects-paradigm
sibling, Vic's) on incrementality / complexity / correctness / parity, **not** on
wall-time. Built foundation-first: the `gen-rebuild` rebuilder lib (done), then a
**parity harness** (done — the measurement substrate), then **the engine** on top
(← you are here).

## Where we are (roadmap)

- **Phase 0 Research ✅** — adios/adios-flake + zen evaluated; cortex profiled (the
  pivot); hola reframed to graph-paradigm + non-perf value.
- **Phase 1 Theory ✅** — 3 canonical rebuilder papers; ~18-op `gen-rebuild` surface.
- **Phase 2a Spec ✅ / 2b Plan ✅** — `gen-rebuild` design (reviewed twice) + v1 plan.
- **Phase 2b EXECUTION ✅** — `gen-rebuild` v1 built (`~/Documents/repos/gen-rebuild`,
  github:sini/gen-rebuild).
- **Phase 3 paradigm GO/NO-GO ✅ = GO** — the B demo (override-store == from-scratch
  over the seeded soundness property) validated graph-based incremental override.
- **`gen-rebuild` v2 ✅ (final-review in flight)** — full rebuilder domain
  (strategies / provenance / drivers / restabilize) + the generic gen-scope/gen-graph
  seams. *Parallel agent is finishing the final review pass; confirm main green
  before the engine consumes it. (Index memory records v2 main @ 97c9af3, 179 tests +
  REFERENCE.md — verify against the agent's update.)*
- **Phase 4 increment 1 — PARITY HARNESS ✅ (built + pushed)** — the engine's
  executable contract. Repo `~/Documents/repos/hola`, **public github:sini/hola**
  (GitHub Actions runs `nix flake check`). Dual-runs nixpkgs `lib.evalModules`
  against a future engine arm and proves byte-identical results. **The measurement
  substrate the engine needs now exists** — and it already self-validates
  (vanilla == identity over all 6 fixtures incl. real-host `toplevel.drvPath`
  byte-identical) and earned its keep (pinned a real nixpkgs surprise: same-priority
  same-order `listOf` defs merge in REVERSE decl order).

## The next phase = YOUR job (Phase 4 increment 2 — the engine arm)

The contract exists; the rebuilder foundation exists. Build the engine and run it
**through the existing harness**.

1. **Confirm the inputs are landed.** `gen-rebuild` main green (ask the parallel
   agent / `cd ~/Documents/repos/gen-rebuild/ci && nix flake check`). hola harness
   green (`cd ~/Documents/repos/hola/ci && nix flake check` — THE authoritative gate,
   29 tests; `nix-unit --flake .#tests` CLI under-reports, do NOT use it).
2. **Design + plan the engine** (brainstorming → writing-plans → subagent-driven,
   fresh-eyes review loops). The engine = a **lib-shaped drop-in** `{ lib; evalModules }`
   that slots into `adapter.engines.engine` (the seam is already there, **proven
   ready by injection** — a third engine record runs through `valueEq`/`drvEq`/
   `expectThrowFx` unchanged). Three pieces, per the reconciled Phase-2 architecture:
   - **Own `modules.nix`** for the per-host submodule shape-hoist (cost-center D).
     HC5 is the load-bearing gotcha: `lib.extend`'s 2-attr inject reaches only the
     ROOT; `extendModules` (modules.nix:386) calls the LOCAL let-bound `evalModules`,
     so per-submodule-element it's bypassed → you must **BE `lib.modules.evalModules`**
     (replace the body), not inject. (This is exactly why the harness made engines
     RECORDS and `runHost` threads `engine.lib` into eval-config.)
   - **Host `lib.types` merge VERBATIM** (HC3/HC4): call the single `type.merge loc
     defs` uniformly; do NOT reimplement the merge kernel (mutually recursive with
     evalModules, value-shape-dispatched, positional, throws). gen-merge is at most an
     OPTIONAL scalar-priority pre-pass.
   - **External lazy module SELECTION from the HOAG graph** (HC7) — the
     differentiator (supply deps externally, vs PR #148456's per-module hand
     annotation). Consume `gen-rebuild` v2 for the **sound incremental** re-eval.
3. **Engine-parity tests against the contract.** Add suites asserting
   `valueEq engine vanilla` / `drvEq engine vanilla` / `expectThrowFx engine`
   over the corpus. The contract already proves `vanilla == identity`; the new work
   proves `vanilla == engine` — OR documents each deliberate divergence and shows the
   real-host `toplevel.drvPath` stays **byte-identical** (the HC2 GO/NO-GO gate:
   nix-diff vs vanilla on a real systemd host = the net-demand-forced-savings
   measurement, which the real-host fixture + `drvPathGate` now make a one-liner).

## Load-bearing decisions & constraints (do NOT relitigate without cause)

- **Pure-gen / GRAPH, not effects.** zen is reference/comparator only — derive
  convergences (located cycles, blame, mk* priority) from graph principles; don't
  port zen's effect implementation. Compare empirically AT THE END.
- **PURE-ONLY.** The impure cross-eval "external shell" (amortized `dirty`/`gc`/
  persisted-mutable-trace) is **out of scope** — a different *stateful* substrate.
  Pure gen-rebuild is the complete pure-Nix rebuilder (revalidation rides Nix
  laziness free; only invalidation amortization needs impurity, H6). Cross-eval
  *result* reuse = the Nix store (deep-constructive via IFD), build-cost-shaped.
- **Host `lib.types` merge VERBATIM** — own only the outer shape + a scalar priority
  pre-pass. **Own `modules.nix`** (BE `lib.modules.evalModules`) for the submodule
  shape-hoist; `lib.extend` reaches only root level.
- **External lazy module selection** from the HOAG graph is the differentiator.
- **HC2 win is real but UNMEASURED-net** — gate on `shorthandOnlyDefinesConfig=true`
  (only shape-invariant elements share; module-carrying `systemd.services` elements
  defeat the hoist → gate + fallback). The GO/NO-GO is the real-host drvPath diff.
- **cortex's ~50s is INTRINSIC** (derivation construction, GC-bound on ~235M copies)
  — NOT a module-system problem; belongs to the **evaluator layer** (Lix / Determinate
  parallel-eval), a deferred separate track, never a hola daemon.
- **Constraints to obey:** per-host engine constraints **K1–K9** + verified claims
  **H1–H7**. H1 = the // copy-storm floor (~1.756M copies just to import nixpkgs) —
  untouchable; all wins are NET of it, incrementality is intra-eval only.

## References (exact)

| What | Where |
|---|---|
| Project home (research, surface, roadmap) | `~/Documents/papers/hola-architecture/` (github.com/sini/hola-architecture, **private**) |
| — Phase 1 (H1–H7) | `analysis/phase-1-feasibility.md` |
| — Phase 2 seed (K1–K9, engine constraints) | `analysis/phase-2-implementation-seed.md` |
| — gen-rebuild surface (~18 ops, seams S1–S9) | `analysis/gen-rebuild-surface.md` |
| — overall roadmap | `PLAN.md` |
| — evidence (cortex profile, workflow JSONs, fixtures) | `analysis/experiments/` |
| **Parity harness spec + plan** | `specs/2026-06-23-parity-harness-design.md`, `plans/2026-06-23-parity-harness.md` (+ `.tasks.json`) |
| **hola code — parity harness (DONE)** | `~/Documents/repos/hola` (**public github:sini/hola**) — `lib/{parity,adapter,corpus,compose}.nix`, `ci/` (gate + Tier-2 apps); engine seam = `adapter.engines.engine` |
| gen-rebuild spec + analysis + plan | `~/Documents/papers/den-architecture/gen-specs/gen-rebuild/` (github.com/sini/den-ag-design) |
| **gen-rebuild code (v1+v2 done)** | `~/Documents/repos/gen-rebuild/` (github:sini/gen-rebuild) — confirm main green |
| theory papers | `den-ag-design/reference-catalog/` + `used/summaries/` — Mokhov-2018, Forgy-1982, Radul-2009, Arntzenius-2016, Acar-2002, Adapton, RTD, etc. |
| gen ecosystem deps | `~/Documents/repos/{gen,gen-graph,gen-scope,gen-derive,gen-schema,gen-aspects,gen-algebra,...}` — gen has the `extraModules` mkCi seam (pushed d65b213) |
| zen (reference, Vic's) | `~/Documents/repos/zen` (github:denful/zen) — effects/streams: bend/ned/nix-effects |
| adios / adios-flake / nixpkgs | `~/Documents/repos/{adios,adios-flake,nixpkgs}` |
| nix-config (integration target) | `~/Documents/repos/sini/nix-config` (colmena fork, dendritic; cortex host) |
| Memory | `~/.claude/memory/{project_hola,project_zen_vic}.md` |

## How we work (methodology)

- **Research** → multi-agent **Workflow** (ultracode): parallel source-grounded
  readers → synthesis → **adversarial 3-lens verification** of load-bearing claims.
  Claims grounded in real source (file:line), measured with `NIX_SHOW_STATS`.
- **Design** → brainstorming → **writing-plans** (bite-sized TDD tasks) →
  **subagent-driven-development** (fresh implementer per task + two-stage review:
  spec compliance then code quality). **Fresh-eyes review loops** on every spec/plan
  — they keep catching real bugs (engine-lib/eval-config seam hole, expectThrow
  polarity, withOptionShape `_module` leak were all caught this way). Use them.
- **gen principle:** each lib is a **complete, faithful** implementation of the ONE
  theory domain it cites. Run **gen-theory-conformance** at each lib gate.
- **Honesty discipline:** report findings straight (the cortex pivot, refuted
  claims, the reverse-order merge surprise). Don't let a reframe inflate confidence
  past the evidence.

## Standing preferences / gotchas

- **Authoritative hola gate = `cd ci && nix flake check`** (→ `checks.default`).
  The `nix-unit --flake .#tests` CLI under-reports hola's multi-suite enumeration
  (gen-canonical `import ../.` subflake quirk) — do NOT use it as the gate.
- **Specs/plans → papers repos** (`~/Documents/papers/<proj>-architecture/`),
  **never** `docs/superpowers/`.
- **No native CC `TaskCreate`** during plan execution — the `pre-commit-check-tasks`
  hook blocks all commits while tasks are incomplete. Use plan checkboxes +
  `.tasks.json`.
- **Hook-removal denials are load-bearing:** if a stale `.git/hooks/pre-commit`
  blocks a commit, do NOT `rm` it (classifier denies as guardrail tampering) — ask
  the user to commit, or refresh the devshell.
- **`gh gist edit` is sandbox-blocked** (group-ID error). Update in place with
  `gh api -X PATCH /gists/<id> --input -` (jq `--rawfile` payload).
- **Commits:** no Co-Authored-By, no bylines; stage specific files (never `-A`);
  `cd ci && nix fmt` before committing.
- **nix-config:** `~/Documents/repos/sini/nix-config` (NOT `~/Documents/repos/nix-config`).
- **Date:** convert relative dates to absolute when recording.

## First action for the resuming session

Confirm `gen-rebuild` main is green (parallel agent's final-review outcome) and the
hola harness gate is green (`cd ~/Documents/repos/hola/ci && nix flake check`, 29
tests). Then **brainstorm + design the engine arm** (Phase 4 increment 2): the
lib-shaped `{ lib; evalModules }` drop-in that owns `modules.nix`, hosts `lib.types`
verbatim, selects modules externally from the HOAG graph, and consumes `gen-rebuild`
v2 — slotting into `adapter.engines.engine` and proving `vanilla == engine` (or
byte-identical-drvPath divergence) through the existing parity contract.
