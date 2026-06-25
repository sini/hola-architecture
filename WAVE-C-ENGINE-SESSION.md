# Wave C — hola engine arm (Phase 4 increment 2)

> Session prompt for the **critical-path** hola work: build the engine that hosts
> unmodified nixpkgs modules and proves byte-identical through the parity harness.
> This is the differentiated value of the whole project — Den integration,
> cross-scope sharing, and the zen comparison all gate on it. Dated 2026-06-24.
> Pairs with `RESUME.md` (broad context), `project_hola` memory, and the
> Phase-2 seed (`analysis/phase-2-implementation-seed.md`, constraints K1–K9).

## Mission

Build the **engine arm**: a lib-shaped `{ lib; evalModules }` drop-in that hosts
*unmodified* nixpkgs/NixOS modules, slots into `adapter.engines.engine` (the seam is
already there, **proven ready by injection**), and proves `vanilla == engine` — or a
documented byte-identical-`drvPath` divergence — through the existing parity harness.

## Prerequisites (confirm before starting)

- **gen-rebuild v2 is the foundation** (main @ 97c9af3, 179 tests). Build on **v2** —
  do NOT wait for v3. Confirm from the v3 review that v3 is **API-additive** (it should
  be: frontier/exact-AFFECTED/constructive are new ops); if so, v2's surface is stable
  to build on and v3 lands independently. (Rule from the dispatch order: let the engine
  *inform* v3's exact-AFFECTED design, not block on it.)
- **Parity harness exists + green** — `github:sini/hola`; gate = `cd ci && nix flake
  check` (NOT `nix-unit --flake`, which under-reports). Engines are RECORDS
  `{ lib; evalModules }`; `runHost` threads `engine.lib` into eval-config; `identity` =
  `lib.extend` passthrough; the `engine` slot is the placeholder you fill.
- **Phase 3 B-demo passed** (the paradigm GO). 
- **Ideally Wave A done** (nix-config + hola CI on CppNix) so byte-identity is proven on
  the evaluator users run. Not a hard blocker, but the right substrate/corpus.

## The three pieces (reconciled Phase-2 architecture — do NOT relitigate)

1. **Own `modules.nix` (the HC5 seam).** `lib.extend`'s 2-attr inject reaches only the
   ROOT; `extendModules` (modules.nix:386) calls the LOCAL let-bound `evalModules`, so
   per-`attrsOf`/`listOf` submodule element it's bypassed. To own cost-center D you must
   **BE `lib.modules.evalModules`** (replace the body), not inject. The harness already
   encodes this (records + `runHost`).
2. **Host `lib.types` merge VERBATIM (HC3/HC4).** Call the single `type.merge loc defs`
   uniformly. Do **not** reimplement the merge kernel — it's mutually recursive with
   evalModules, value-shape-dispatched (`anything`), positional for same-priority merge,
   and throws (not a total lattice). gen-merge is at most an optional scalar-priority
   pre-pass.
3. **External lazy module SELECTION from the HOAG graph (HC7) — the differentiator.**
   Supply which-modules-fire as graph edges (vs PR #148456's per-module hand annotation).
   Consume gen-rebuild v2 (`build`/`override`/`affectedSet`) for sound incremental re-eval.

## Sub-increments (build in this order; each parity-gated)

- **E1 — byte-identical hosted-merge owning `modules.nix`.** The minimal lib-shaped
  drop-in: own the evalModules body, host `lib.types` verbatim, no selection yet. **Gate:**
  `valueEq engine vanilla` + `drvEq engine vanilla` green on the EXISTING corpus
  (synthetic / landmines / real-host). This is the load-bearing proof: a reimplemented
  engine that's still byte-identical. Hardest, highest-value — do it first and fully.
- **E2 — Den-as-corpus.** Add Den's real flake-output + per-host module sets to the
  harness; prove byte-identical on real, unmodified configs. This is the **bridge to Den
  integration** (Wave D) — once green, Den's swap is just pointing `outputs.nix` at the
  engine behind the oracle.
- **E3 — external lazy selection + gen-rebuild incremental.** Wire the HOAG selection +
  gen-rebuild reuse. **Gate:** still byte-identical, AND measure the selection/incremental
  win on iterative eval (the assembly slice, not the intrinsic floor).

## Method

The user's standard: **brainstorming → writing-plans → subagent-driven-development**,
fresh-eyes review on every spec/plan (they keep catching real bugs — the harness itself
had the engine-lib/eval-config seam hole, the expectThrow polarity, the `_module` leak,
all caught this way). The **parity harness is the continuous gate**. Spec + plans →
`~/Documents/papers/hola-architecture/{specs,plans}`, NEVER `docs/superpowers/`. Opus for
the non-mechanical subagents.

## Constraints & gotchas (load-bearing)

- **K1–K9** (per-host engine constraints) + **H1–H7** (verified claims) — full text in
  `analysis/phase-2-implementation-seed.md` / `phase-1-feasibility.md`.
- **H1 = the //-floor** (~1.756M copies just to import nixpkgs) — every win is NET of it;
  incrementality is **intra-eval only**.
- **K9 fragility:** owning `modules.nix` + hosting `type.merge` pins to nixpkgs *internal*
  API — each nixpkgs bump is a gated migration. Accept it; the parity harness catches
  breakage. (This is also why Wave-A CppNix matters: pin/migrate against the reference.)
- **Known surprise the harness already pins:** same-priority same-order `listOf` defs
  merge in REVERSE declaration order. The engine must reproduce it.
- **Don't chase the cold-eval wall here** — that's the Determinate/evaluator track. The
  engine's value is correctness + incrementality + external selection, NOT single-host
  wall-time (the cortex profile settled that).

## Gate (the Phase-4 success criteria)

- Byte-identical `system.build.toplevel.drvPath` on a real host (E1/E2).
- Value + throws parity on the corpus (`valueEq`/`drvEq`/`expectThrowFx engine vanilla`).
- Incremental override works on real unmodified nixpkgs modules (E3).
- Complexity / parity compared to zen (the standing comparison axis).
- Either `vanilla == engine` everywhere, OR each divergence documented + shown
  byte-identical at the `drvPath` tier.

## References

| What | Where |
|---|---|
| Broad resume / engine-arm context | `RESUME.md` |
| Parity-harness spec (the contract) | `specs/2026-06-23-parity-harness-design.md` |
| Engine constraints K1–K9 | `analysis/phase-2-implementation-seed.md` |
| Verified claims H1–H7 | `analysis/phase-1-feasibility.md` |
| Roadmap (Phase 4, Phase 4.5) | `PLAN.md` |
| hola code (harness + engine seam) | `~/Documents/repos/hola` (`github:sini/hola`) — `adapter.engines.engine` |
| gen-rebuild (the foundation) | `~/Documents/repos/gen-rebuild` (`github:sini/gen-rebuild`) — confirm v2 main green |
| Memory | `~/.claude/memory/{project_hola,project_gen_rebuild,project_zen_vic}.md` |

---

*Wave C of the agreed dispatch order: the critical-path mission spine. Runs after the v3
review confirms v2's API is stable (parallel-repo to v3, not serial). Den integration +
cross-scope sharing (Phase 4.5) + the zen comparison all gate on E1/E2 being
byte-identical. Determinate (Phase 2) is the separate opportunistic velocity track —
keep it from pulling focus off this.*
