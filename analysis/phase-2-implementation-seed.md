# `hola` — Phase 2 Synthesis & Implementation Brainstorm Seed

**Companion to [`phase-1-feasibility.md`](./phase-1-feasibility.md). Do not edit
that file; this one supersedes its forward-looking sections under the expanded
"reimplement the engine" scope.**

> Purpose: this is **not a design** — it is the verified constraint set, the
> measured cost map, the reusable methods, and the open decisions that a
> Phase-3 *implementation brainstorm* will resolve. Everything below is grounded
> in two adversarial research workflows (57 agents, ~4M tokens total) that ran
> live experiments against `~/Documents/repos/{nixpkgs,adios,gen,den}` and
> `~/Documents/repos/zen`. Where a claim was refuted, it is marked — several
> refutations *improved* the design.

---

## 0. The thesis after two phases + zen

`hola` = a flake+module framework that hosts **unmodified nixpkgs/NixOS modules**
and evaluates faster than `lib.evalModules` + flake-parts, via a **pure-gen,
graph-based** paradigm (HOAG typed-edge graph + gen-scope), deliberately *not*
effects-based. zen (Vic's) is the **reference/comparator**, not the basis;
greenfield. The four-part architecture the evidence now supports:

1. **A HOAG graph plane drives EXTERNAL lazy module selection** — the
   composition-axis win (~30%, the only axis measured to speed up) *and* the
   open-niche differentiator.
2. **Host `lib.types` merge VERBATIM** — do not reimplement the merge kernel
   (the refutation that most shaped the design).
3. **A reimplemented `modules.nix` engine owns `extendModules`** for the
   per-host submodule-shape hoist — real and byte-identical, but **net delivered
   magnitude is unmeasured** and is the go/no-go gate.
4. **All wins NET of the intrinsic `//`-storm floor**; all incrementality
   intra-eval.

---

## 1. Verified constraints (the rules implementation must obey)

Each is grounded; the bracket cites the claim id and the strongest lens that
upheld/refuted it across both workflows.

- **K1 — The `//`-storm is intrinsic and untouchable.** `import <nixpkgs> {}` +
  `attrNames` = **1,756,265 copies** before any output is forced
  (`fixed-points.nix:333` `extends`). A real `system.build.toplevel.drvPath` =
  **~4.7M fn-calls / ~12.2M copies**; disabling `_module.check` moves copies
  **−0.2%**, drvPath byte-identical. *Measure every win NET of this base.*
  [HC6 ×3 upheld; H1]

- **K2 — No cross-process persistence.** Lambdas are non-serializable
  (`toJSON`/`toString` of a function throw; `functionArgs` sees no captured env);
  the flake eval-cache keys only locked-rev leaf values. **All incrementality is
  intra-eval.** Cross-host/cross-CLI reuse needs an out-of-language store (IFD /
  CA cache / Lix plugin) — outside the pure-framework scope. [HC6 ×3; H6]

- **K3 — Host `lib.types` merge VERBATIM; do not reimplement it.** `type.merge`
  is mutually recursive with `evalModules` (`submodule.merge.v2` =
  `base.extendModules` = a fresh recursive eval, `types.nix:1445-1461`),
  dispatches on *runtime* value shape (`anything`), is *partial* (throws on
  conflict, not a total lattice join), and is **positional** for same-priority
  value merge (`listOf [1,2]` then `[3,4]` → `[3,4,1,2]`; `lines` order-sensitive).
  A self-contained `gen-merge` byte-matching the wrapper×type cross-product
  *would have to be the evaluator*. **Call the single `type.merge loc defs`
  interface uniformly** — the legacy `loc: defs:` arrow is the uniform interface
  across **all** types (most types are plain `loc: defs:` functions —
  `mergeEqualOption`/`mergeOneOption`/`lines`/`commas`/`attrs`…; only the
  submodule/attrsOf/listOf/either/coercedTo family carries a `__functor`+`.v2`,
  and for them the arrow already returns `(self.v2 {…}).value`). So no v2
  dispatch is needed. **Caveat:** calling the legacy arrow drops `valueMeta`,
  which is *documented public API* (`option-types.section.md`) with `lib/tests`
  coverage — so `options.*.valueMeta` parity is a **D5 parity-bar item**, not a
  throwaway. [HC3 ×3 refuted→hybrid; HC4 ×3 refuted→simplify]

- **K4 — Owning cost-center D requires *being* `modules.nix`, not injecting.**
  `lib.extend` over `{evalModules, modules.evalModules}` intercepts only the
  **root** eval level. `extendModules` (`modules.nix:386`) calls the
  modules.nix-**local** let-bound `evalModules`, so the overlay is **structurally
  bypassed for every `attrsOf`/`listOf` submodule element** (verified
  `extendedPostmark=false`). To attack the per-host submodule cost the engine
  must replace the `modules.nix` body and own the recursion. "No fork / two attrs
  / complete" is self-contradictory for the D path. [HC5 refuted ×2]

- **K5 — Dependency declaration must be EXTERNAL/contract-based, never
  inferred.** The single `evalModules` option namespace is flat and
  non-statically-partitionable (`declsByName = zipAttrs (map .options)`,
  `modules.nix:789`); a module's `config.*` read-set is not statically
  recoverable (`functionArgs` name-only; 274 dynamic `config.${k}` selects;
  `doRename` cross-module aliasing; `with`). The only clean partition boundary is
  the submodule (a nested eval). **Therefore hola's dependency graph comes from
  the HOAG plane, supplied externally — not inferred from module bodies.** [H3, H4]

- **K6 — Lazy module SELECTION is the proven lever, and external graph
  declaration is hola's differentiator.** No project hosts unmodified nixpkgs
  with a faster *reimplemented* merge. The closest precedent — a-la-carte
  **PR #148456 (CLOSED)** — did lazy module-skip via an options-fixpoint, reached
  **~40%**, but stalled on **per-module hand-declared `enabledBy`/`requires`** +
  CI scale. hola supplies exactly those declarations from the HOAG graph, without
  touching modules. [HC7 ×2 upheld]

- **K7 — Parity has an 80/20 core and a long failure-mode tail.** Frequency-
  anchored core: 5 property wrappers (`mkIf` 5034 / `mkDefault` 1832 / `mkMerge`
  553 / `mkForce` 107 / `mkOverride` 70) + the discharge/filter/sort pipeline;
  ~12 types with both legacy and v2 merge; the flat config fixpoint +
  `_module.args`/`specialArgs`; split-declaration `mergeOptionDecls`;
  `extendModules` as a stable user-facing primitive; the `doRename` rename-forward
  path (1521 cross-module readers). **Three silent-mis-eval landmines** (each
  type-checks clean, ships a derivation that *builds but differs*): **L1** a
  high-priority whole-attrset def *evaporates* normal-priority sibling keys
  (`filterOverrides` picks over the whole-option def list *before* `attrsOf`
  descends); **L2** `attrsOf` vs `lazyAttrsOf` `mkIf false` strictness flips
  `cfg ? attr`; **L3** the v2 `{headError,value,valueMeta}` triple coherence.
  Error-message/provenance fidelity (`_file`, declaration positions, `showDefs`,
  levenshtein suggestions) is a **separate bar** to decide explicitly. [parityVerdict]

- **K8 — `specialArgs` / `_module.args` threading is load-bearing.** The engine
  must reproduce `specialArgs` (set as `_module.specialArgs`, merged into every
  module's args) and **re-thread it through `extendModules` and the submodule
  `base.extendModules`** (`modules.nix:252,261,390`; `types.nix:1454`), plus the
  `_module.args` collision/override semantics. Because K4 mandates owning
  `extendModules` *and* the submodule recursion, this contract sits on the hot
  path for both the D-hoist and `nixosSystem` hosting — not optional. (phase-1's
  gen-bind `wrapAll` is the arg-collision precedent.)

- **K9 — hola is pinned to nixpkgs *internal* API.** Hosting `lib.types` merge
  verbatim + owning `modules.nix` couples hola to unstable internals
  (`type.merge` arity, the v2 triple shape, `extendModules`/`collectModules`
  signatures) that nixpkgs changes without notice (v2 merge itself is recent,
  2025-08→2026-05). A nixpkgs bump is a **gated migration guarded by the parity
  harness**, never a free input update. [HC4 timeline; parityVerdict residual leak]

---

## 2. The cost map (what we attack, what we don't)

Re-tiered under a custom engine. "intrinsic" = survives a full reimplementation;
"machinery" = attackable by owning the engine. Numbers are measured.

| Center | What | Tier under custom engine | Measured |
|---|---|---|---|
| **A** | Eager shape transpose (`zipAttrs` declsByName/pushedDownDefs) | **Partly attackable**: per-element re-payment inside submodules hoistable (→D); the top-level key-union stays intrinsic (K5 — can't prune) | reading 1 leaf ≈ forcing `attrNames` (601K fn, read-independent); but ~60%/98% of that is `_module.check` (B), not the floor |
| **B** | `_module.check` unmatched-defn walk | **Machinery — need never be built** | FIXED **~110,035 fn/level**, doesn't scale with N; drvPath byte-identical with `check=false` |
| **C** | Per-option value merge (priority/discharge/sort/`type.merge`) | **Intrinsic (K3)** — semantics must run; single-def leaves hit the ~free fast path (`modules.nix:1214-1235`) | extra merged def ≈ 67 fn/element |
| **D** | Submodule recursion (`base.extendModules` per element) | **The per-host prize — partly attackable** (memoize shape-invariant base; re-run per-element value merge) | real systemd: **4,559 fn / 6,500 thunks / 1,911 copies per element**, flat; shared-shape sim **111,159 vs 358,723 fn = 69%** (N=250/B=20), byte-identical |
| **E** | `//`-storm | **Intrinsic floor (K1)** | submodule recursion = **0.017%/element** of copies; the bulk is `import nixpkgs` |

**The contested number.** The 30–71% D-axis "prize" is a *synthetic ceiling*.
HC1's decomposition (67% hoistable re-collection) was **refuted** — its indirect
method reclassified intrinsic demand-driven per-option merge as hoistable. On a
*real* systemd host forcing unit `.text`, merge dominates (forcing one leaf = 19
fn/svc). The hoist is mechanically real and byte-identical (HC2 upheld) but the
**net delivered fraction on a demand-forced `toplevel` is unmeasured** and is
conditioned on element shape-invariance. The gate is **per-def-within-element,
not per-element**: `allModules` (`types.nix:1380`) branches on `isAttrs value &&
shorthandOnlyDefinesConfig` *per definition*, so an element is shareable only if
**all** its defs hit the `config = value` branch; a single function/`imports`-
valued def (or `shorthandOnlyDefinesConfig=false`, as on `systemd.services`)
takes the `imports = [value]` path, can declare new options, and defeats sharing
for that element → gate at the `allModules` branch level and fall back to full
re-collection.

---

## 3. The architecture sketch (4 planes) — for the brainstorm to refine

```
 ┌── PLANE 1: HOAG GRAPH (pure gen, no evalModules) ──────────────────────┐
 │  nodes = entity scopes (hosts/aspects/regions); edges = S/T/P/M +       │
 │  specificity D<I<P. Drives:                                            │
 │   • EXTERNAL lazy module selection (which modules apply to which host) │
 │     — the #148456 enabledBy/requires graph, supplied from gen not hand │
 │   • settings precedence default<env<host<policy (gen-algebra foldLayers)│
 │   • which-aspect-fires (gen-derive dispatch)                          │
 │  → emits an ORDERED module list per host (ordering is load-bearing —    │
 │    merge is positional, K3; see D2 emit contract).                     │
 │  (the measured ~30% is the MULTI-SYSTEM flake-output axis, NOT the      │
 │   per-host selection win, which is unmeasured)                         │
 └───────────────────────────────┬───────────────────────────────────────┘
                                  │ module list (no evalModules yet)
 ┌── PLANE 2: hola ENGINE (reimplemented modules.nix; OWNS extendModules) ┐
 │  • collects + transposes the submodule declaration SHAPE once per      │
 │    submodule TYPE (the D-hoist); per-element runs only leaf value merge │
 │  • skips _module.check construction for trusted leaves (B)            │
 │  • demand-driven shape where sound (A, gen-lazy)                      │
 │  • installed as lib.modules.evalModules (K4: must BE it, not wrap)    │
 └───────────────────────────────┬───────────────────────────────────────┘
                                  │ at each option leaf
 ┌── PLANE 3: HOSTED lib.types MERGE (verbatim, K3) ──────────────────────┐
 │  call `type.merge loc defs` uniformly (legacy = v2 .value). The        │
 │  priority/discharge/sort PRE-pass may be a small optional gen-merge    │
 │  scalar component; the recursive type-merge is lib's, byte-for-byte.  │
 └───────────────────────────────┬───────────────────────────────────────┘
                                  │
 ┌── PLANE 4: INTRINSIC FLOOR (K1/K2) — import<nixpkgs>, //-storm ────────┐
 │  ~12.2M copies on a real toplevel. Untouchable. Measure NET of it.     │
 └────────────────────────────────────────────────────────────────────────┘
```

**Contrast with zen (the comparison axis).** Same per-host target, opposite
trades: zen **replaces** merge (bend lenses; byte-identical `str`/`listOf str`
only → faster, partial compat) and hoists submodules via `fx.rotate` scope
boundaries (effects). hola **hosts** `lib.types` merge (full compat by
construction → speed-ceilinged) + owns the engine for the D-hoist + drives
selection via the graph (pure values). zen = effects/streams; hola =
graph/attribute-grammar. **This trade-off is an architectural hypothesis, not a
measured result** — no zen-vs-hola benchmark exists or is yet scoped; "settle
empirically at the end" is a deliberate future step, not a planned bench in this
phase.

---

## 4. Methods we developed (reusable in implementation)

These are the *experimental apparatus* the implementation phase reuses to
validate every step — the most transferable output of the research.

1. **Dual-run parity harness.** `realLib.evalModules` vs `customLib.evalModules`
   over one shared module set in one eval → `configDiff=[]`, `optionNamesEqual`,
   `getSubOptions` identical. Demonstrated working. Extends to the option-TYPE
   plane (gen-schema parity) and to a `system.build.toplevel.drvPath` `nix-diff`.
   **Makes the reimplementation testable INCREMENTALLY (swap engine, keep diff
   green) instead of big-bang.** This is the single most important method.

2. **`NIX_SHOW_STATS` cost decomposition.** `nrFunctionCalls` / `nrThunks` /
   `nrOpUpdateValuesCopied` deltas under `nix-instantiate --eval --strict`,
   scaling N and isolating centers (e.g. `check=true` vs `false`; 1-unit vs
   50-unit; shape-force vs config-force). The discipline that caught HC1's
   artifact: **measure on the real demand-forced workload, not a synthetic.**

3. **lib-injection seam.** `lib.extend` threads through `nixosSystem` →
   `eval-config.nix:32` → `evalModules`/`types` (`makeExtensible`/`callLibs`).
   Verified — *but only to the root level* (K4). The method is real; its limit
   is the design constraint.

4. **Shared-shape engine simulation.** Collect base option-tree once, per-element
   `evalOptionValue` against shared decls → 69% fn-call reduction byte-identical
   on a synthetic. The prototype skeleton for the D-hoist.

5. **Trace-on-force read-capture.** A tagged tracing `config` view via
   `applyModuleArgs` makes leaves `builtins.trace "READ:<path>"` — fires iff
   forced, survives the full merge, recovers the leaf read-set of *unmodified*
   modules for ONE drvPath force. Out-of-band (stderr), two-process, intra-eval.
   **Soundness hole:** it captures the demand set of a single force, so it
   validates *no-spurious* edges but **cannot prove *no-missing* edges** unless
   run under a full-config force (not demand-driven). A fallback/oracle for
   external declaration, not a completeness proof for HOAG edges.

6. **Adversarial-claim workflow.** Reader fan-out → synthesizer emits falsifiable
   load-bearing claims → 3 diverse lenses each try to *refute* with live
   experiments. This is how we'll vet implementation claims too (e.g. "the
   shared-shape engine is byte-identical on a real host").

---

## 5. Open decisions for the brainstorm (the actual forks)

These are unresolved and are what Phase 3 must decide. Each has a recommendation
to argue *against*, not to rubber-stamp.

- **D1 — Engine ownership depth.** Full reimplemented `modules.nix` owning
  `extendModules` (K4, needed for the D-hoist) vs a vendored/patched `modules.nix`
  vs a thin shape-cache shim (rejected — can't reach D). *Lean: own a minimal
  `evalModules` core, host `lib.types` at the leaf.* How much of the 2000-line
  surface (K7) is in v1?

- **D2 — The HOAG graph model, concretely.** Nodes = ? (hosts/aspects/regions),
  edges = ? (S/T/P/M), and exactly how the graph expresses (a) external module
  selection and (b) the `enabledBy`/`requires` dependency declaration that
  replaces #148456's hand annotation. Built on gen-scope (`lib.fix` + `_eval`
  memo). What's the node/edge type, and what does the graph emit per host?
  **The emit contract must be pinned:** an *ordered* module list (merge is
  positional, K3 — wrong order = a silent L-class byte-divergence), where the
  `imports`-closure resolution and `disabledModules` handling happen (graph vs
  engine), and whether the graph emits pre-`import` paths or evaluated module
  attrsets.

- **D3 — `gen-merge` scope (if any).** Build the optional scalar-priority
  pre-pass (discharge→filter→sort) in gen, or call lib's `mergeDefinitions`
  pipeline too and own *only* the outer shape? K3 says the recursive type-merge
  is lib's regardless. Is a gen scalar-priority module worth it, or pure overhead?
  *Lean: call lib's full `mergeDefinitions`; revisit only if profiling demands.*

- **D4 — Incremental override mechanism.** Declared HOAG edges (graph-native,
  sound, K5/K6) vs runtime trace-on-force (observed, out-of-band, method 5).
  *Lean: declared edges; trace-on-force as a validation oracle, not the
  mechanism.* Bounded by K2 (intra-eval).

- **D5 — Parity bar.** Config/drvPath byte-identity is the floor. Decide the
  **failure-mode** bar: match error-message provenance (`_file`, positions,
  suggestions) or accept degraded diagnostics in v1? (K7 tail.)

- **D6 — gen integration & new modules.** Map gen-scope/gen-schema/gen-derive/
  gen-algebra to Planes 1–2. Do we need new gen modules — `gen-lazy` (first-order
  lazy constructors for demand-driven shape, Lorenzen-2025), a scalar
  `gen-merge`? Or does existing gen + hosted lib.types suffice? Note H5 dissolves
  (we control the deferredModule contract), so gen introspection can target the
  hola engine — but inverting `gen-schema`'s `deferredModule` base
  (`entry-type.nix:32`) is a real, unestimated refactor.

- **D7 — Spike sequencing** (see §6).

- **D8 — Distribution & flake-output surface.** K4 means hola *cannot* ship as a
  thin `lib.extend` overlay (bypassed for submodules) — the reimplemented
  `modules.nix` must enter **every host's `lib` closure**. Decide: vendored
  `lib` fork vs nixpkgs overlay vs patched-input; and the consumer surface
  (flake template? `lib.nixosSystem` drop-in? a `mkFlake`?). This is a real
  distribution problem, not a packaging afterthought.

---

## 6. The go/no-go gate + spike plan

**The gate that decides whether the *per-host* prize is real:**

> Prototype the shared-shape engine (reimplemented `extendModules` owning the
> submodule recursion), run it on a **real systemd-heavy host**, `nix-diff`
> `system.build.toplevel.drvPath` against vanilla `lib.nixosSystem`, measure
> **NET** `nrFunctionCalls`/`nrThunks` savings on the *demand-forced* workload —
> **and** confirm **no single-def fast-path regression** (the ~free common case,
> `modules.nix:1214`): a byte-identical engine even 1.2× slower per ordinary leaf
> loses on every host. All three conditions must pass.

Green diff + net savings + no fast-path regression → the D-axis win is real, build
it. Otherwise hola's win is the **multi-system composition axis only** (the
measured ~30% is that *flake-output* axis; the per-host selection win is
separately unmeasured) — still worthwhile, still graph-native, still the open
niche — and per-host stays Phase-1's verdict.

Spike order — **front-load the measured, lower-risk win; gate the speculative
one** (each uses the dual-run harness; each asserts `toplevel.drvPath` byte-parity
at its own step, not deferred to the end):

1. **S0 — Parity harness + adversarial corpus.** Dual-run over a real host's full
   `module-list.nix` *and* a targeted fixture corpus for the K7 landmines (L1
   whole-attrset evaporation, L2 `attrsOf`/`lazyAttrsOf` `mkIf false`, L3 v2
   triple + `valueMeta`) and the 5 wrappers; run hola's engine through nixpkgs'
   own `lib/tests/modules.sh` as a conformance oracle. Identity engine must give
   `configDiff=[]` + identical `toplevel.drvPath`. *(method 1)*
2. **S1 — Hosted-merge engine.** Minimal reimplemented `evalModules` owning shape
   but calling `lib.types` `type.merge` verbatim (K3) + the K8 specialArgs
   contract. Assert drvPath parity **and** the no-fast-path-regression floor
   *here*, not only at S2.
3. **S3 — HOAG selection plane (bank the measured win first).** External lazy
   module selection from a gen-scope graph; pin + prove the D2 emit contract +
   end-to-end drvPath parity; measure the composition-axis win. Lower-risk and
   measured — de-risks the program before the speculative hoist.
4. **S2 — The D-hoist (the go/no-go gate).** Shared-shape memoization + the
   per-def shape-invariance gate (§2) for module-carrying elements; run the gate
   experiment above. *Justify building this before S3 only if S3 proves
   insufficient.*

---

## 7. Anti-scope — what we will NOT build (from the refutations)

- **Do not reimplement `type.merge`** (K3/HC3). Host `lib.types`.
- **Do not dispatch on `merge.v2`** (HC4). One uniform `type.merge loc defs` call.
- **Do not infer read-sets statically** (K5/H4). Declare externally via HOAG.
- **Do not inject the D-path via `lib.extend`** (K4/HC5). Own `modules.nix`.
- **Do not expect cross-process memo** (K2/H6). Intra-eval only.
- **Do not chase the `//`-storm** (K1). It's `import nixpkgs`, not us.
- **Do not assume the 30–71% per-host number** until S2 measures it net on a real
  host (HC1 refuted, HC2 conditioned).
- **v1 hosts NixOS modules only.** home-manager / nix-darwin each build their own
  `evalModules` chains needing the patched `lib` per-framework — out of scope for
  v1 (else you fork three engines).
- **Do not bump nixpkgs without the parity harness** (K9): the rev is pinned;
  internal-API drift is a breaking change, not a free input update.

---

## 8. Known unknowns (carry into the brainstorm)

- Net delivered per-host % on a *real demand-forced* `toplevel` (S2 gate).
- The fraction of real `attrsOf (submodule)` elements that are shape-invariant
  (shareable) vs module-carrying (must fall back).
- Cost of inverting `gen-schema`'s `deferredModule` base to target the hola
  engine (D6).
- Per-option overhead of any gen-level merge dispatch vs lib's builtin-heavy
  native fast path (the "3–10× slower per option → net loss on single-host"
  risk; relevant only if D3 builds a gen-merge).
- The provenance-fidelity bar (D5) and its implementation cost.
- home-manager / nix-darwin each build their own `evalModules` chains needing the
  patched lib per-framework (unmapped residual leak).

---

## 9. Brainstorm opening frame

Three questions to open Phase 3 with:

1. **Engine shape:** what is the minimal reimplemented `evalModules` core that
   owns `extendModules` and hosts `lib.types` merge — and what's deferred to v2?
   (D1, K3, K4)
2. **Graph model:** what are the HOAG nodes/edges that supply external module
   selection + dependency declaration, on gen-scope? (D2, K5, K6)
3. **First proof:** is S2 (the D-hoist drvPath-parity gate) the right first
   build, or do we prove the composition-axis graph win (S3) first since it's the
   measured, lower-risk ~30%?

---

*Synthesized from `hoag-nixpkgs-feasibility` (Phase 1) and
`hola-full-hoag-evaluation` (Phase 2) workflows + the zen source read. All
file:line and measured figures are against the local checkouts at the revisions
of 2026-06-23.*
