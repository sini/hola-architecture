# hola Parity Harness — Design Spec

> **Status:** approved design, pre-implementation (revised after fresh-eyes review).
> **Date:** 2026-06-23.
> **Increment:** hola Phase 4, first deliverable. Built in parallel with `gen-rebuild` v2.
> **Repo (to create):** `~/Documents/repos/hola` (`github:sini/hola`).
> **nixpkgs rev for all §3/§4 line citations:** `2f4f625e` (the pinned experiment rev; §4 line
> numbers are rev-sensitive and must be re-verified on a nixpkgs bump — same discipline D7 mandates
> for report counters).

## 1. Context & motivation

hola is a pure-gen / graph-paradigm Nix module engine that hosts *unmodified*
nixpkgs/NixOS modules. Its value is **sound incremental override**, **correctness**
(located cycles, no-throw accumulating blame, inspectable composition), and
**external lazy module selection** — judged against zen (the effects-paradigm
sibling) on incrementality / complexity / correctness / parity, **not** on wall-time
(see `analysis/phase-1-feasibility.md`, the cortex pivot in `project_hola` memory).

Phase 4 — "the engine on nixpkgs" — has three subsystems:

1. **Parity harness** — dual-run vs `lib.evalModules`, byte-identical gate.
2. **Hosted-`lib.types`-merge engine** that owns `modules.nix` (the submodule shape-hoist).
3. **External lazy module selection** from the HOAG graph (the differentiator).

Only subsystem 1 has **zero dependency on `gen-rebuild`**. Subsystems 2–3 consume
the rebuilder, whose v2 is in flight. Therefore this increment builds **only the
parity harness**, for three reasons:

- It cannot be invalidated by `gen-rebuild` v2 (its ground truth is "vanilla
  `lib.evalModules` is correct," which is invariant).
- It is the **oracle the engine validation requires** — when the engine lands we
  need byte-identical proof immediately.
- Building it forces us to pin down what "parity" *precisely* means before the
  engine architecture is committed, which tightens that later design.

The engine is deliberately **held for landed-and-validated v2** to avoid designing
against a moving target. Harness now ∥ v2 now → both land → engine designed against
concrete artifacts.

### The harness is the engine's executable contract

This is the spine of the design. The parity harness is **not a benchmark**. It is the
**operational definition of "faithfully hosts unmodified nixpkgs modules"**:
projection-value-equal `config` plus drvPath-string-identical `toplevel`, plus the merge
landmines (priority fold, order-sensitivity, conflict-throws, valueMeta) *are* the contract.

**Soundness scope (honest caveat):** value-tier parity is only as complete as each fixture's
`pick` projection — config outside the picked surface is *unverified*. The contract's strength
is the union of the corpus's projections, not whole-config identity. The drvPath tier closes this
for whole NixOS hosts (one string covers the realized system); the synthetic/landmine tiers are
projection-scoped by construction (you cannot force a raw `config` full of derivations).

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Full parity substrate + perf-decomposition substrate (Tier-2, scaffolded, non-gating) in v1** | Consolidate the scattered absolute-path evidence fixtures into one turnkey parameterized harness; the perf substrate is then ready the moment the engine + D-hoist arrive. **No v1 perf number is a deliverable claim** — the Tier-2 apps measure the vanilla baseline only (no engine arm exists yet); their curves become meaningful when the engine lands. |
| D2 | **Tiered oracle**: config projection-value-diff (synthetic/landmine) + `toplevel.drvPath` string-identity (real host) | config-diff locates *where* a wrong engine diverged; drvPath gives end-to-end identity without forcing the lazy tree. Matches `hc5_parity` + cortex-profile. |
| D3 | **Stat axis = secondary, caveated** | Cheap (cortex `NIX_SHOW_STATS` recipe). **The gate is projection-value/drvPath correctness; no measured number is ever pass/fail.** A build-smoke (does the app *run*) may gate app-health, but never a threshold. |
| D4 | **Architecture C** — two-tier: contract-as-lib (Tier 1, CI-gated) + evidence-as-flake-apps (Tier 2) | Maps onto D1–D3; keeps the contract as Nix tests; isolates unavoidable bash to the perf layer. |
| D5 | **Tier 2 = flake apps via the gen ci devshell**, hosted through a new `extraModules` seam on `gen.lib.mkCi` (§14) | `writeShellApplication`, deps pinned in closure, `nix run ./ci#…`; reproducible, no PATH/chmod fragility. |
| D6 | **List compare is exact / order-sensitive** | Parity demands it — `mkBefore`/`mkAfter`/`mkOrder` produce specific orders (hc3_l1). zen's order-insensitive `srt` compare is rejected for the parity gate. |
| D7 | **nixpkgs injected via arg / flake input** | Fixes the hardcoded `2f4f625e` absolute-path blocker in the existing fixtures; record rev + nix version in every report (counters are version-sensitive). |

## 3. Reuse map

The harness is ~80% assembly of existing artifacts, not net-new invention.

| Need | Existing artifact (grounded) | Action |
|---|---|---|
| Dual-run skeleton + projection idea | `analysis/experiments/claim-proofs/hc5_parity.nix:6-49` (realLib vs `realLib.extend` identity-passthrough; asserts configDiffEmpty/optionNamesEqual/getSubOptionsIdentical) | lift the dual-run + projection idea; **§6 `withOptionShape` augments the value-tier `pick` with option-name/`getSubOptions` data so both flow through one `diff`** — lifts the idea, not a verbatim lift |
| Merge-landmine corpus | `hc3_l1.nix:12,19,21` (mkOrder/mkAfter/mkBefore **and** priority fold→`["c"]`), `hc3_order.nix:9` (mkBefore only), `hc3_lattice.nix` (int/double-mkForce throws), `hc3_meta.nix` (valueMeta escape) | port as the must-match gate |
| Synthetic scaling corpus | `cost-decomposition/dual.nix:1-22` (knobs n/ndecls/layers), `dual2.nix` | port, parameterize nixpkgs |
| Real-host corpus | `cost-decomposition/realsvc.nix`, `checktest.nix:1-20` (eval-config, N systemd.services, `_module.check` toggle) | port (drvPath gate) |
| H1 floor baselines | `phase1-cost/bench_just_import.nix:2` (import+attrNames = 1,756,268 copies), `bench_lib_only.nix`, `bench_mod_scale.nix` | port as perf-subtraction baselines |
| Stat capture recipe + JSON schema | `experiments/README.md:13-15` + `cortex-profile/m3-top.json` (nrFunctionCalls/nrThunks/nrOpUpdateValuesCopied/nrPrimOpCalls/gc.totalBytes/cpuTime) | lift recipe |
| Cost+equality driver, doubling-ratio table, report template | zen `benchmarks/run-realistic-bench.sh`, `run-chain-bench.sh`, `verify.nix`, `RESULTS-realistic.md` | adapt into flake apps |
| Repo skeleton + nix-unit + mkCi convention | `gen-rebuild` root `flake.nix`/`default.nix`/`lib/default.nix` fold; `ci/flake.nix`→`gen.lib.mkCi`; `ci/tests/*.nix` `flake.tests.<suite>.<test>`; `.envrc`/CI/README/LICENSE; `.github/FUNDING.yml` | clone the **structure**; the leaf `default.nix` arg shape mirrors **gen-aspects** (a true `{ lib }` leaf), not gen-rebuild (which takes graph+scope) |

adios provides **no** turnkey byte-identical comparator (`adios-flake/BENCHMARKS.md` is prose-only,
measured across two migrated external commits). Borrow only its `NIX_SHOW_STATS` A/B protocol and the
value-identity memoization probe. Lesson absorbed into D1/D7: **vendor a fixed parameterized corpus**,
never measure across migrated external commits.

## 4. Oracle grounding (`nixpkgs/lib/modules.nix`, rev `2f4f625e`)

- `evalModules` returns `{ _type; options; config; _module; graph; extendModules; type; class }`
  (`modules.nix:399-406`). `config` = the option tree with each leaf option replaced by its merged
  `.value` (`modules.nix:283`), `_module` removed. `graph` is re-collected via `doCollect {}` — an
  engine reimplementing `modules.nix` must reproduce graph-collection only if a fixture's projection
  touches it (none do; value-tier picks stay graph-free).
- **Value tier (synthetic / partial):** projection-value-compare a **force-safe projection** of
  `result.config`. Never compare `result.options` — it holds functions, `unsafeGetAttrPos` locations,
  and thunks that are never equal.
- **Whole-host tier (NixOS):** compare `config.system.build.toplevel.drvPath`
  (`nixos/modules/system/activation/top-level.nix:160-167`, `types.package`, readOnly) — one string
  transitively covering the realized system, avoiding a forced lazy-tree walk.
- `_module.check` is a `seq`-forced throw (`modules.nix:304-378`); it and `class`
  (`eval-config-minimal.nix:40`) **must be held identical across A/B** or parity is incomparable —
  the corpus enforces this as a precondition (§6 `drvPathGate`).
- **Engine seam (HC5, confirmed):** `submoduleWith` binds the *local* `evalModules`
  (`types.nix:1375,1393`); per-element re-eval goes via `base.extendModules`
  (`types.nix:1452-1455`) whose body calls the bare local `evalModules` (`modules.nix:386`). So
  **`lib.extend` overrides are bypassed for every submodule child** (proof:
  `claim-proofs/hc5-test/probe5.nix`). The engine arm must therefore be a **lib-shaped drop-in**
  capturing both `lib.modules.evalModules` *and* the submodule `extendModules` — not an overlay.

## 5. Architecture — two tiers, one repo

New repo `~/Documents/repos/hola`, gen-canonical, **leaf-for-now** (`{ lib }` only; the engine
increment adds gen-scope/gen-graph/gen-rebuild deps). The harness is hola's permanent test substrate;
the engine lands in the same repo.

```
hola/
  flake.nix              # root: lib = import ./. { lib = nixpkgs.lib; }; __functor = _: import ./.
  default.nix            # { lib }: import ./lib { inherit lib; }   (leaf, mirrors gen-aspects)
  lib/
    default.nix          # // fold of concern modules
    parity.nix           # TIER 1 oracle: diff · locate · drvPathGate · expectThrow · withOptionShape
    adapter.nix          # evalAdapter seam: engines.{vanilla,identity} + run  (engine arm added later)
    corpus/
      default.nix        # registry: { name; mk; defaultParams; gate; tier }
      synthetic.nix      # dual.nix-style {lib,n,ndecls,layers} -> package-free NixOS-shaped
      landmines.nix      # hc3_* ported: priorityFold · order · latticeThrows · valueMeta
      real-host.nix      # eval-config-backed {lib,nixpkgs,n} -> NixOS host (drvPath gate)
      floor.nix          # H1 baselines: justImport · libOnly · modScale (perf-only)
  ci/
    flake.nix            # gen.lib.mkCi { ... extraModules = [ ./apps.nix ]; }
    apps.nix             # flake-parts module: perSystem.apps.{stat-capture,scaling-curve,floor-decomp,parity-report}
    tests/               # = testModules; import-tree sweeps ONLY this dir
      smoke.nix
      parity/{self-parity,landmines,oracle}.nix
    bench/               # writeShellApplication payloads wired to apps.nix  (NOT under testModules)
  README.md · LICENSE · .envrc · .github/{workflows/ci.yml, FUNDING.yml} · .gitignore   (from gen-rebuild)
```

`bench/` lives under `ci/` (tooling, not lib — root stays pure lib) but **outside** `testModules`
(`= ./tests`), so import-tree never sweeps `writeShellApplication` modules as malformed `flake.tests`
entries (`mkCi.nix:44` scopes import-tree to the passed dir).

## 6. The fixture/oracle contract (the spine)

Comparison is **projection-based**: a fixture declares its own force-safe comparison surface, so the
oracle never blindly `deepSeq`s a `config` full of derivations / functions.

```nix
fixture = {
  modules;              # the SAME unmodified nixpkgs-shaped modules fed to both engines
  specialArgs ? {};
  class ? null;         # "nixos" for hosts — held identical across A/B
  pick    = config: …;  # force-safe projection (value tier): MUST return only
                        #   strings/ints/bools + lists/attrsets thereof — no derivations/functions
  gate    = "value" | "drvPath" | "throws";
  expected ? null;      # consulted IFF gate=="value"; MUST be null for "throws"/"drvPath"
};
```

`lib/parity.nix` — four comparators + one projection helper:

- `force = x: builtins.deepSeq x x` — full-forces a projection. Safe **by the `pick` contract**: a
  fixture whose `pick` leaks a derivation/function is a *fixture bug*, not a harness concern.
- `diff { a, b }` → `{ identical :: bool; divergences :: [ { path; aValue; bValue } ] }`:
  - Each arm is first wrapped `builtins.tryEval (force arm)`. If exactly one arm throws → a single
    root divergence `{ path = []; aValue/bValue = "<<throw>>" }`. If both throw on a `value` fixture
    → fixture mis-categorization, reported as a root divergence.
  - `path` = a list of attr keys / list indices from the projection root, e.g.
    `[ "things" "web" "enable" ]`.
  - Recursion: at each node, if **both** sides are attrsets, recurse over
    `union(attrNames a, attrNames b)`; a key present in exactly one side is a divergence carrying the
    present value and the sentinel `"__absent"` for the missing side. If **both** are lists, compare
    length first (mismatch = one divergence at the list path), then element-wise by index
    (**order-sensitive**, D6). Otherwise compare by `==` (leaf). `identical = divergences == []`.
- `locate { a, b }` → the head of `diff`'s `divergences` (first divergence; the debugging entry point
  for a wrong engine).
- `drvPathGate { a, b }` → `builtins.tryEval`s `config.system.build.toplevel.drvPath` on each arm and
  compares the strings; a throw on either arm → divergence (never an abort). **Precondition:** applies
  only to fixtures with `gate="drvPath"` (the registry guarantees these are `class="nixos"` real hosts
  with identical `_module.check`); applying it to a synthetic fixture is a registry-rejected error.
- `expectThrow = engine: fx: !(builtins.tryEval (force (pick (run engine fx)))).success` (the `throws`
  gate) → returns **did-throw** (`true` when the projection threw). Throw **messages are deliberately
  NOT compared** — merge-error text is not a stability contract, so the throws tier is explicitly
  weaker than value/drvPath and documented as such.
- `withOptionShape { options ? null; subOptionPaths ? {}; }` → a **pick-builder**, not a comparator:
  augments a fixture's `pick` with the option-name set (`options` if given, else
  `attrNames result.options`) and, per entry in `subOptionPaths` (option → `loc`),
  `attrNames (result.options.<opt>.type.getSubOptions loc)` (single-level descent; `loc` = the option
  path with `"*"` for attrsOf/listOf submodules, e.g. `[ "svc" "*" ]` — matching `hc5_parity.nix:41`).
  Option-name/`getSubOptions` parity thus flows through the same `diff` as values; no separate
  comparator.

**Terminology:** "**projection-value-equal**" = `diff.identical` over a `pick` surface;
"**drvPath-string-identical**" = `drvPathGate.identical`. "byte-identical" is reserved for the drvPath
string case where it is literally true.

## 7. Adapter seam (`lib/adapter.nix`)

```nix
engines = {
  vanilla  = args: lib.evalModules args;     # reference
  # identity: a lib.extend passthrough — byte-identical OUTPUT, but routes through the SAME override
  # seam (and the submodule extendModules bypass, §4 HC5) the real engine arm will later replace.
  identity = args: (lib.extend
    (final: prev: { modules = prev.modules // { evalModules = a: prev.modules.evalModules a; }; })
  ).evalModules args;
  # engine = args: hola.evalModules args;    # ADDED in the engine increment (lib-shaped drop-in)
};

# applies the schema `?` defaults (inherit would THROW on an omitted optional field):
run = engine: fx: engine ({ inherit (fx) modules; specialArgs = fx.specialArgs or {}; }
  // (if (fx.class or null) == null then { } else { inherit (fx) class; }));
```

`class = null` means the field is **omitted** from the `evalModules` args (vanilla default applies);
only string classes (`"nixos"`) are forwarded. `lib` / `nixpkgs` injected via arg → fixtures portable
(D7). The engine arm (later) is a lib-shaped drop-in capturing both `lib.modules.evalModules` and the
submodule `extendModules` (§4, HC5).

## 8. Corpus (`lib/corpus/`)

Each entry: `{ name; mk = params: fixture; defaultParams; gate; tier = "parity" | "perf" | "both" }`.
All parameterized; `lib`/`nixpkgs` via arg. The plan enumerates the **exact** source file per entry
and lists the experiment files explicitly **not** ported (avoid carrying the experiment sprawl —
`realsvc{,_opts,_one,_demand,_probe}.nix`, `dual` vs `dual2`, ~20 `hc2_*` variants — into the new repo):

- **synthetic** ← `dual.nix` — `{ lib, n, ndecls, layers }` → package-free NixOS-shaped module set
  (attrsOf submodule, scalars, listOf, mkMerge priority layers, sparse cross-ref). `gate = "value"`.
- **landmines** ← `hc3_{l1,order,lattice,meta}.nix`, each with a known resolved `expected`:
  `priorityFold` (→`["c"]`), `order` (mkBefore/mkAfter/mkOrder — note mkAfter/mkOrder live in
  `hc3_l1`), `latticeThrows` (`gate = "throws"`, `expected = null`), `valueMeta`.
- **realHost** ← `checktest.nix` (eval-config form) — `{ lib, nixpkgs, n }` → full NixOS host, N
  systemd.services; `gate = "drvPath"`.
- **floor** ← `bench_{just_import,lib_only,mod_scale}.nix` — H1 baselines; `tier = "perf"`, no parity
  gate — the subtraction baselines for `floor-decomp`.

## 9. Data flow

```
fixture ─run(engine)─▶ evalResult ─pick─▶ projection ─┬─ parity.diff   (projection-value)   ─▶ nix-unit assert  [Tier 1]
                                                      └─ drvPathGate   (drvPath string)      ─▶ nix-unit assert
fixture ─▶ bench app ─▶ NIX_SHOW_STATS json ─extract─▶ delta / doubling-ratio / floor-subtract table             [Tier 2]
```

## 10. Tier-1 tests (work today, no engine)

nix-unit `flake.tests.<suite>.<test> = { expr; expected; }` modules, auto-discovered by import-tree,
gated by `cd ci && nix flake check`:

- `self-parity.nix` — every parity fixture: `run vanilla` vs `run identity`. For `value`/`drvPath`
  gates, asserts identical; for `throws`, asserts `expectThrow vanilla fx == expectThrow identity fx`
  **and** both `== true` (both arms throw). **What this proves:** determinism + that the **top-level**
  `lib.extend` override seam is *transparent* (an identity override does not perturb output), and that
  the submodule `extendModules` path — which the override **bypasses** (§4 HC5) — is left unmodified.
  It does **not** prove the submodule seam is transparent *under an override* (only testable once the
  engine arm captures `extendModules`), nor that the oracle can *detect* a divergence.
- `oracle.nix` — **this is the oracle-soundness proof.** Unit-tests `diff` / `locate` / `drvPathGate`
  directly: equal projections → `identical`; projections differing at path `p` → a divergence at `p`;
  missing-key → `"__absent"` sentinel; list order/length divergences; one-arm-throw → root divergence.
  Establishes the *discrimination* power self-parity cannot.
- `landmines.nix` — every hc3_* fixture: `gate="value"` → `pick (run vanilla fx) == expected`;
  `gate="throws"` → `expectThrow vanilla fx` (asserts it threw). Locks the must-match contract values.

Future (engine increment, seam ready): `engine-parity.nix` = `run vanilla` vs `run engine` for every
fixture = the engine's acceptance gate. **Out of scope here.**

## 11. Tier-2 evidence — flake apps (D5)

`pkgs.writeShellApplication { runtimeInputs = [ nix jq hyperfine ]; }`, wired to `perSystem.apps` via
`ci/apps.nix` (§14) + available in `nix develop ./ci`. **No measured number ever gates CI**; an
optional build-smoke (does the app evaluate/run at all) may gate *app health* only. Fixtures are
addressed by registry `name` (`corpus/default.nix`); params via `--params k=v,…` mapped to the
fixture's `mk`. Every app records the nixpkgs rev + nix version (D7). Exit 0 always (evidence apps):

| App | Args | stdout / output |
|---|---|---|
| `stat-capture` | `<fixtureName> [--params n=…,ndecls=…]` | one-line JSON `{ nrFunctionCalls, nrThunks, nrOpUpdateValuesCopied, nrPrimOpCalls, gcTotalBytes, cpuTime, nixpkgsRev, nixVersion }` (cortex `NIX_SHOW_STATS` recipe) |
| `scaling-curve` | `<fixtureName> --sweep n=64,128,256,512` | table rows `{ n, counter, costN, cost2N, ratio }` (→2 linear, →4 quadratic; zen `run-chain-bench`) |
| `floor-decomp` | `<fixtureName>` | captures floor baselines (justImport/libOnly/modScale) + fixture; table `{ component, fnCalls, copies, attributed }` (leaf-vs-toplevel; cortex decomposition) |
| `parity-report` | `[--out PATH]` | markdown report: Tier-1 pass/fail (the real gate is `nix flake check`) + stat deltas; zen `RESULTS` template with an honest-caveat + **nixpkgs-rev & nix-version pin** header |

## 12. Error handling / correctness constraints

- Compare only over `pick` projections (force-safe by the `pick` contract); never `deepSeq` the whole
  `config`. **Value-tier parity is projection-scoped — un-picked config is unverified** (§1 caveat).
- All comparators internally `tryEval` each arm; a throw is a *divergence*, never a suite abort.
- Throw-landmines via `tryEval` (hc3_lattice: int-conflict / double-mkForce throw); messages not compared.
- `_module.check` + `class` held identical across A/B (§4) — corpus-enforced precondition.
- nixpkgs via arg / flake input; record rev + nix version in every report (D7); §4 line citations are
  pinned to rev `2f4f625e`.
- Counters (deterministic) are the metric; wall-time is caveated / secondary (D3).

## 13. Out of scope (YAGNI / honesty)

The engine itself (next increment, after v2) · engine-parity tests (seam only) · cross-eval
persistence / impure caching (PURE-ONLY decision) · wall-time as a gate · any v1 perf number as a
deliverable claim.

## 14. Prerequisite — `gen.lib.mkCi` apps seam (resolved)

Verified: `mkCi` has **no** apps/extraModules seam (signature `{ inputs, name, testModules,
specialArgs ? {} }`, `mkCi.nix:13-22`), and its return value is the sealed `mkFlake` result
(`mkCi.nix:29-46`) — you **cannot** bolt `perSystem.apps` on after the call. So Tier-2 requires a
small, generally-useful change to shipped gen (consistent with improving APIs; the gen CI surface
hasn't ossified):

- Add `extraModules ? [ ]` to `mkCi`'s signature; append: `imports = [ … (import-tree testModules) ] ++ extraModules;`.
- hola `ci/flake.nix` passes `extraModules = [ ./apps.nix ]`, a flake-parts module setting
  `perSystem.apps`.

**Composition-safety (verified):** `flakeModule.nix` sets no `perSystem.apps`; flake-parts' core
`apps` option is free, so an `extraModules`-supplied apps module merges additively — no collision.
This is a standalone gen change (a one-liner + test), landed before hola's `ci/` can expose apps.

## 15. References (grounded; nixpkgs rev `2f4f625e`)

| What | Where |
|---|---|
| Existing dual-run skeleton | `analysis/experiments/claim-proofs/hc5_parity.nix` |
| Merge landmines | `analysis/experiments/claim-proofs/hc3_{l1,order,lattice,meta}.nix` |
| Synthetic / real / floor corpus | `analysis/experiments/cost-decomposition/{dual,dual2,realsvc,checktest}.nix`, `phase1-cost/bench_*.nix` |
| Stat recipe + JSON schema | `analysis/experiments/README.md:13-15`, `cortex-profile/{m1-hostname,m3-top}.json` |
| Engine seam proof (HC5) | `analysis/experiments/claim-proofs/hc5-test/probe5.nix`; `nixpkgs/lib/{modules,types}.nix` (§4) |
| zen bench methodology | `~/Documents/repos/zen/benchmarks/{run-realistic-bench,run-chain-bench,bench}.sh`, `verify.nix`, `RESULTS-realistic.md` |
| gen-* repo convention | `~/Documents/repos/gen-rebuild/{flake.nix,default.nix,lib,ci}`; `~/Documents/repos/gen-aspects/default.nix` (leaf shape); `~/Documents/repos/gen/ci/{mkCi,flakeModule}.nix` |
| Engine constraints (K1–K9, H1–H7) | `analysis/phase-2-implementation-seed.md`, `analysis/phase-1-feasibility.md` |
| Roadmap / resume | `PLAN.md`, `RESUME.md` |
