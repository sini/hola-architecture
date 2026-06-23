# `hola` — Phase 1 Feasibility Analysis

**A HOAG/gen-ecosystem alternative to adios & adios-flake that *retains* nixpkgs
module compatibility while shedding NixOS-module-system evaluation overhead.**

> Provisional codename **`hola`**: adios ("goodbye") replaces the NixOS module
> system with a smaller one; `hola` ("hello") keeps nixpkgs and its module
> content, and attacks the *machinery* cost instead. Rename at will.

---

## 0. Document provenance

- **Date:** 2026-06-23
- **Lens:** feasibility of building a new flake+module framework on the gen
  ecosystem (gen-schema / gen-aspects / gen-algebra / gen-derive / gen-bind /
  gen-scope) + the den HOAG edge model, that hosts **unmodified nixpkgs/NixOS
  modules** yet evaluates faster than `lib.evalModules` + flake-parts.
- **Method:** 28-agent adversarial research workflow (`hoag-nixpkgs-feasibility`,
  ~1.85M tokens, 979 tool calls). Six parallel source-grounded readers
  (nixpkgs `lib/modules.nix`, `lib/types.nix`; adios engine; Nix evaluator perf
  model; gen ecosystem; HOAG/scope-engine) → one synthesizer → 7 load-bearing
  claims each adversarially attacked through 3 diverse lenses
  (nixpkgs-source-reality, eval-semantics-soundness, implementation-realism).
- **Confidence:** all 7 load-bearing claims **survived** refutation
  (`refuted=false` on every valid lens; one H6 verdict returned malformed and is
  discarded — its two other lenses upheld). Numbers and file:line references
  below are reproduced from agents that ran `NIX_SHOW_STATS` /
  `nix-instantiate --eval` against the local checkouts
  (`~/Documents/repos/{nixpkgs,adios,adios-flake,gen}`).

---

## 1. Executive verdict

**The central question — "can we keep nixpkgs and its complexity but optimize
the eval/laziness to avoid the full module-system cost?" — answers YES, but only
for a specific and bounded slice, and NOT the slice most people assume.**

Three facts fix the answer:

1. **The biggest single cost metric is intrinsic to nixpkgs *content*, not the
   module system.** Abandoning the entire NixOS module system (adios-flake vs
   flake-parts) reduces values-copied-via-`//` by only **−0.3 %**
   (1,851,228 → 1,846,322 single-system). The `//` storm is the *package-set
   fixpoint* (`lib/fixed-points.nix:333` `extends`), forced by the mere act of
   `import <nixpkgs> {}` (~1.756M copies *before any output is forced*). No
   compat-preserving framework can touch it. (Claim **H1**, verified by
   independent `NIX_SHOW_STATS` decomposition.)

2. **The only *measured* speedup (~28–30 % CPU) is on the
   flake-output/multi-system axis** — `perSystem` packages/formatter/devShells
   over 36 inputs × 3 systems, where flake-parts re-pays module machinery
   *per system* and adios shares it once. **There is no measurement, and no
   mechanism, for making a single `nixosSystem`'s internal `evalModules`
   cheaper.** adios buys its speed precisely by *not hosting* nixpkgs modules.
   (Claim **H2**.)

3. **Retaining nixpkgs option *content* forces a real type-driven merge**
   (`mkOverride` priority + `mkIf` discharge + `mkOrder` sort + `type.merge`
   submodule recursion) to run *somewhere*. **No gen primitive reproduces it**
   (gen-algebra `foldLayers` is priority-blind/position-driven; gen-derive
   resolves *which rules fire*, not how *values* merge). The intrinsic per-host
   merge cost can only be **relocated** to one terminal `evalModules` and
   shared/deferred around — never eliminated. (Claim **H7**, byte-divergence
   empirically demonstrated.)

So `hola`'s realizable win is **"adios-flake-class speedup on the
composition/multi-system axis while keeping nixpkgs leaves opaque and
compat-exact"** — by moving *composition* (host/aspect/setting resolution) off
`evalModules` onto a pure gen-scope graph, and confining `evalModules` to one
terminal materialization per host. It is **not** "make a single host's module
evaluation cheap."

The naive premise to kill up front: **"build on gen ⇒ avoid the module
system" is false.** gen-schema and gen-aspects are built *on top of*
`lib.types.deferredModule` and force `lib.evalModules` on introspection
(`entry-type.nix:32`, `:223`). gen as-shipped **adds** module machinery; the
correct architecture uses gen for the *off-module graph plane* and confines the
module system to terminal leaves. (Claim **H5**.)

---

## 2. The cost model — where a real NixOS/flake eval actually spends

Ranked, eager-first. Lettered for reference by the candidate table (§4).

### (A) EAGER phase-1 shape construction — *the largest unavoidable-on-any-read cost*
`merged = mergeModules prefix (reverseList (doCollect {}).modules)`
(`modules.nix:275`) is demanded by **any** read of `config`/`options`. It:
- (i) imports every transitively-imported module file (`import m`,
  `modules.nix:449-451`) and resolves the full `imports` closure via
  `genericClosure` de-dup (`:564-573`);
- (ii) canonicalizes each module (`unifyModuleSyntax`, `:634-702`);
- (iii) reflects each module function's formal-arg **names** via `functionArgs`
  (`applyModuleArgs`, `:724-732`);
- (iv) builds the option/definition **shape**: `declsByName = zipAttrs(map
  .options)` (`:789-808`), `pushedDownDefinitionsByName = zipAttrsWith
  concatLists (map .config)` (`:831-852`), pushing `mkIf`/`mkMerge`/`mkOverride`
  *down* (`pushDownProperties`, `:1335-1356`), calling `unsafeGetAttrPos` per
  option name.

This is the **O(#modules × #option-paths)** transpose, eager in `attrNames` at
every nesting level, **independent of which config attr you read**.

### (B) EAGER `_module.check` shape-force
Default `true`; `checked = seq checkUnmatched` wraps options/config/_module
(`:378`, `:401-402`). `checkUnmatched` (`:304-376`) forces
`merged.unmatchedDefns` = a `removeAttrs` over the **complete attrName set** of
options vs config at every level (`:927-956`). A *second* full shape walk.
**Skippable** via `check = false` or a `freeformType` (`:305`) — a real tunable.

### (C) LAZY phase-2 per-option value merge
Scales with options *actually demanded*, not declared.
`evalOptionValue → mergeDefinitions` runs `dischargeProperties` (mkIf) →
`filterOverrides'` (priority) → `sortProperties` (mkOrder) → `type.merge` per
demanded option (`:1100-1311`), with an explicit **fast path** for the
single-unwrapped-definition case (`:1214-1235`) that most option reads hit.

### (D) LAZY-but-multiplicative submodule recursion — *the dominant cost in a fully-forced real config*
Every `attrsOf`/`listOf (submodule …)` runs **one fresh independent
`evalModules` per element** via `base.extendModules`
(`types.nix:1452-1455 → modules.nix:380-393`). `systemd.services/sockets/timers/
targets/paths` and `mounts/automounts` are all `attrsOf/listOf (submodule …)`
(`nixos/lib/systemd-types.nix:131-227`); a system with N units pays ~N nested
collect+merge passes, nesting compounding to **O(N×M)**. `mergeModules'` even
auto-wraps every bare dotted option subtree in a synthetic `submoduleWith`
(`:855-871`). Bounded by laziness to demanded paths, but
`system.build.toplevel` forces the product.

### (E) The `//` copy storm
~1.85M values-copied single-system, ~3.55M three-system
(`BENCHMARKS.md:36,49,62`). Each `//` copies all attribute **slots** (key +
thunk pointer, lazy in values) of both operands. Concentrated in nixpkgs import
+ per-flake-input `packages // legacyPackages` processing
(`adios-flake lib.nix:231-238`), **not** module dispatch. Quadratic under
left-folded `//`; forcing the spine (`attrNames`/`mapAttrs`/`toJSON`) over a
merged set defeats laziness and pays the full copy even without reading values.

**Summary:** SHAPE (A,B) is eager, proportional to declaration size; VALUES
(C,D) are lazy, proportional to demand; the `//` storm (E) is
eager-once-spine-forced and dominated by content, not machinery.

---

## 3. The feasibility crux — intrinsic vs machinery

This separation *is* the answer.

### INTRINSIC (unavoidable while retaining nixpkgs content)
1. **The `//` copy storm.** adios cuts it −0.3 % despite dropping the whole
   module system. These copies are the package-set fixpoint
   (`fixed-points.nix:333` `extends`, `:344-346` `composeExtensions`) + flake-input
   `packages//legacyPackages`. Paid by anyone importing nixpkgs. Empirical floor:
   `import <nixpkgs> {}` forcing only `attrNames` = **1,756,268** copies;
   adding a full `lib.evalModules` on top = **+99**; a complete NixOS config eval
   = only **+~79K (+4.5 %)** over the bare-import baseline.
2. **The terminal per-host option-merge fixpoint.** Two definitions of one
   option merging under `type.merge` with `mkOverride`/`mkIf`/`mkOrder` semantics
   has **no** gen replacement. If you keep nixpkgs option content you must run a
   real merge somewhere.
3. **Import-closure forcing.** `imports` are static-by-design (config-dependent
   imports structurally forbidden, `modules.nix:270` `addErrorContext`), so
   resolving the file graph is intrinsic to honoring nixpkgs modules.

### MACHINERY (potentially avoidable)
The ~60K function-calls + ~50K prim-ops `BENCHMARKS.md:71-76` attributes to
"`evalModules`, option type checking, and merge machinery" — the measured
−26/−29 % function-calls, −30/−44/−47 % prim-ops, −36/−38/−40 % attr-lookups,
−20/−27/−28 % thunks. Specifically:
- (a) the `zipAttrs`/`mergeModules'` per-path **shape transpose** (A) when
  *amortized across a graph of regions/flake-inputs* that re-pay it under
  flake-parts' nested `evalModules`;
- (b) `_module.check` shape-forcing (B) — skippable;
- (c) the doc/description path (`submoduleWith getSubOptions/extendModules`,
  `types.nix:1434,1469-1474`) when never demanded;
- (d) **redundant re-collection of the same system-independent module prefix
  across N systems** — adios-flake's headline win;
- (e) `applyModuleArgs` per-module `mapAttrs`+`//` arg synthesis (`:724-739`).

### Size of the avoidable slice — stated honestly
The **only measured number** is adios-flake's ~28–30 % CPU on a *flake-output*
workload. That is the module-system machinery flake-parts pays **per-system**
and adios shares once. It is **not** a measurement of a single `nixosSystem`'s
internal module cost; there the dominant cost is intrinsic (D + the merge
itself). Therefore the avoidable slice for a compat-preserving framework is
bounded to:
- (i) graph-plane composition cost moved **off** `evalModules` (the adios-flake
  ~30 % class — realizable);
- (ii) cross-system / cross-input **prefix sharing**;
- (iii) skippable **check/doc** paths.

**Not** the intrinsic per-host merge, and **not** the `//` storm. The honest
ceiling: *adios-flake-class speedup on the flake-output/multi-system axis while
keeping nixpkgs leaves opaque* — not *cheap per-host `evalModules`*.

---

## 4. Seven verified constraints (load-bearing claims)

Each survived adversarial refutation on all valid lenses. Stated as the
constraint `hola`'s design must obey, with the sharpest nuance the attack
surfaced.

| # | Constraint | Key nuance from the attack |
|---|---|---|
| **H1** | The `//` storm is intrinsic to nixpkgs content; module-system removal moves it −0.3 %. | Counter `nrOpUpdateValuesCopied` (`eval.hh:1074`) is tied to syntactic `//` at WHNF, ~orthogonal to merge cost. A pure 200-module/10K-value `evalModules` = 683 copies vs 131K fn-calls. The 1.75M floor scales with *packages referenced*, not framework. |
| **H2** | Only the flake-output/multi-system axis is measured to speed up; per-host `evalModules` is unmeasured and unreduced. | Structural, not just unmeasured: `nixosConfigurations` is an opaque flake-scoped passthrough (`adios-flake lib.nix:48-58`); the real `lib.nixosSystem` runs inside the *user's* module impl over `module-list.nix` (2047 base modules), outside adios entirely. |
| **H3** | A single `evalModules` level has a flat, non-statically-partitionable option namespace; the only clean partition boundary is the submodule (already an independent `evalModules`). | `declsByName`/`rawDefinitionsByName` zip ALL module keys by name (`:789-852`); the shared `config` reaches every module via `applyModuleArgs`. Other independent-`evalModules` boundaries exist (`extendModules`, specialisation, the whole `submoduleWith` family) but each is still a *whole sub-evaluation of many modules* — strictly coarser than adios's per-module. |
| **H4** | A module's `config.*` read-set cannot be discovered by pure Nix; external AST parsing is an unsound over-approximation. | `functionArgs` is name-only (`{...}:` catch-all → `{}`). Defeated by dynamic selects (`config.services.${cfg.webserver}`, kimai.nix:14; 54 occurrences), `config`-aliasing (`doRename`, `modules.nix:2028-2061` — from↔to edge lives in a *separate* module), and `with`. Nuance: `with config.X` is prefix-bounded in practice (0 bare `with config;` in nixpkgs), so the blast radius is prefix-local — but the soundness kill is carried by dynamic selects + aliasing regardless. **Exact auto-partition of vanilla modules is impossible; partitioning must be contract-based or conservative.** |
| **H5** | gen-schema/gen-aspects are built *on* the module system; gen as-shipped *adds* machinery. No gen primitive reproduces type-driven submodule merge. | `base = lib.types.deferredModule` (`entry-type.nix:32`); sole introspection path is `lib.evalModules` (`:223`). The `mkType` escape hatch (`:121-141`) skips `evalModules` only by hardwiring `options = {}` — *empty* introspection, i.e. the **C2** architecture (confine to leaf), not evalModules-free introspection. Empirically: the **parent/collection graph plane** IS module-free (pure `foldl'`, `:89-97`); only the **ref/option introspection plane** forces `evalModules`. |
| **H6** | Helpful memoization is strictly **intra-eval** thunk sharing; pure Nix cannot persist/import a forced thunk across `nix eval` invocations. | adios override = `removeAttrs prevEval.{args,results} diff` reusing already-allocated heap thunks (`default.nix:475-476`), closure over live in-process `evalParams`. Functions are non-serializable (`toJSON`/`toString` of a lambda throw); the flake eval-cache stores only shallow flake-output leaf values keyed by locked-rev, never an intermediate thunk/fixpoint cell. **Bounds C1/C6/C8 to one eval; no cross-CLI amortization in pure Nix** (only escape = out-of-language store/IFD). |
| **H7** | Retaining nixpkgs option content forces a real type-driven merge; it can only be relocated to one terminal `evalModules`, not eliminated. | Byte-divergence proven: `[mkForce["c"], mkDefault["z"], normal["n"]]` → nixpkgs `["c"]` (force wins despite being *first*) vs `foldLayers` replace `["n"]` (last positional); `mkIf false` → nixpkgs `["base"]` (def evaporates) which `foldLayers` cannot model. **Narrowing the attack forced:** the irreducible kernel is the *typed option-tree fixpoint walk* + *merge algebra at conflict sites* — single-definition leaves hit the fast path (`:1214-1235`) and are ~free, so a HOAG engine maximizing single-def options pays strictly less, but never zero (`evalOptionValue` always prepends `mkOptionDefault opt.default`, `:1104-1112`, so most options have ≥2 defs). |

**The two design corollaries** (from H3 + H4 + H7):
- Partitioning vanilla nixpkgs is **contract-based or coarse**: the finest
  *sound* boundary you get for free is the **submodule / nested-`evalModules`**,
  i.e. per-host or per-region — **not** per-module like adios.
- The merge is **relocatable, shareable, deferrable — not removable.** Every
  design that claims otherwise must exhibit a gen merger byte-identical to
  `lib/types` submodule merge under `mkOverride`/`mkIf`/`mkOrder`. None exists.

---

## 5. Candidate techniques (C1–C10)

`keepsCompat`: full = hosts unmodified nixpkgs modules; partial = needs opt-in /
loses a semantic; none = adios's road (rejected for `hola`).

| id | technique | targets | keepsCompat | realizable win |
|----|-----------|---------|-------------|----------------|
| **C1** | Memoize system-independent module prefix across systems/inputs | A, E | full | **~28–30 % on multi-system flake outputs (measured); ~0 single host** |
| **C2** | Confine `evalModules` to terminal leaves; composition in pure Nix (HOAG two-plane) | nested-evalModules tax, D | full | **eliminates the per-region evalModules tax without abandoning nixpkgs** |
| **C3** | Partition the config fixpoint via explicit typed HOAG edges | flat namespace, override invalidation | partial | region-granular incremental override — *until an edge crosses into `config`* |
| **C4** | `evalModules`-lite: drop `_module.check`, doc-gen, rare priority paths | B, doc path | partial | one fewer full shape-walk; modest, unmeasured |
| **C5** | Lazy-splice / persistent merge instead of left-folded `//` | E, A | partial | **small** — the `//` bulk is nixpkgs import, off-limits (H1) |
| **C6** | Opt-in edge-annotated incremental modules, full-eval fallback | per-override granularity | full | per-module incrementality *for new annotated code only* |
| **C7** | External static read-set discovery (parse `.nix`) | auto edge discovery | full | enables auto-partition — **but unsound (H4); must over-approximate** |
| **C8** | Coarse-grain per-host / per-flake-input `evalModules` memoization | redundant re-forcing, E | full | dedup duplicate host/input forces within one eval |
| **C9** | Submodule-eval deferral / shared-base hoisting for `attrsOf`-submodule | **D — the dominant real-config cost** | partial | **potentially large IF re-collection (not value-merge) dominates — UNMEASURED** |
| **C10** | gen-derive as rule-activation layer (NOT a merge replacement) | aspect/overlay/policy selection | full | replaces hand-rolled activation with memoized fire-once dispatch |

### Grouping

**Load-bearing (the `hola` core):** **C2 + C1 + C8 + C10.** These are
`full`-compat, realizable, and together constitute "do all composition on a pure
gen-scope graph, share the system-independent prefix, dedup host/input forces,
use gen-derive to pick what applies, and cross into one terminal `evalModules`
per materialized host." This banks the adios-flake ~30 % class **without**
giving up nixpkgs.

**Opt-in / situational:** **C4** (a `check=false`/freeform fast-eval mode for
trusted leaves), **C6** (adios-grade incrementality for *new* `hola`-native
edge-annotated modules, vanilla nixpkgs falling back to opaque leaf), **C3**
(region partitioning — valuable but with the decisive caveat below).

**Weak / rejected as primary:** **C5** (the `//` bulk is intrinsic, H1 —
realizable slice is only the machinery folds), **C7** (unsound auto-discovery,
H4 — only viable as a *conservative* hint that fails open to the prefix; cannot
be load-bearing), and adios's own "replace the module system" road (`none`
compat — that's adios, not `hola`).

### The decisive caveat on C3 (and why `hola` is coarser than adios)
Region partitioning is incremental **at the edge/region boundary, not inside a
nixpkgs module.** The moment an edge crosses *into* `config` you re-couple both
hosts' fixpoints and lose the laziness — the same coupling NixOS has, now
explicit/opt-in. Granularity is structurally **per-host-leaf**, not per-module
(H3). Whether real configs can keep their edges `config`-free is **unestablished
and is a Phase 2 open question.**

---

## 6. Recommended architecture — the two-plane HOAG engine

```
                    ┌──────────────────────────────────────────────┐
                    │  GRAPH PLANE  (pure Nix, NO evalModules)       │
                    │                                                │
   inputs / aspects │  gen-scope lib.fix graph + co-located _eval    │  C1: per-node
   hosts / settings │  memoization (eval.nix:24-53)                  │  thunks pointer-
        ───────────▶│   • structure / host topology  (parent edges) │  identical across
                    │   • aspect resolution          (gen-derive)    │  systems for nodes
                    │   • settings precedence  default<env<host<pol  │  that never read
                    │     (gen-algebra foldLayers, rec.nix:264)      │  the system input
                    │   • activation / which-applies (gen-derive     │
                    │     dispatch: override>priority>exclusive)     │  C8: each host/input
                    │   • HOAG edges S/T/P/M, specificity D<I<P      │  forced once, shared
                    └───────────────────────┬────────────────────────┘
                                            │  resolved deferredModule
                                            │  fragments cross the boundary
                                            │  (gen-aspects mkType, schema.nix:20 —
                                            │   __functor defers evalModules)
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │  MODULE PLANE  (ONE terminal evalModules / host)│
                    │                                                │
                    │  lib.nixosSystem / lib.evalModules over the     │  C4 (opt-in): trusted
                    │  resolved module set + 2047 base modules        │  leaves run check=false
                    │  • nixpkgs modules hosted VERBATIM (gen-bind    │  / freeformType to skip
                    │    wrapAll for arg-collision)                   │  the (B) shape-walk
                    │  • the intrinsic merge (H7) runs here, ONCE     │
                    │  • // storm (H1, E) lives here — unavoidable    │
                    └──────────────────────────────────────────────┘
```

**Boundary discipline (the load-bearing rule, from H5):**
`evalModules` is forbidden in the graph plane and mandatory exactly once per
materialized host leaf. gen-schema/gen-aspects introspection (which forces
`evalModules`, `entry-type.nix:223`) is allowed **only at definition time**, and
the graph plane must build only on the *module-free* gen surfaces (parent /
collection topology, `foldLayers`, gen-derive dispatch) — never on the
ref/option-introspection plane.

**What each piece does:**
- **gen-scope** (`lib.fix` + `_eval` memo) is the spine that gives C1/C8 their
  intra-eval thunk sharing — the analogue of adios's `firstTree.override`,
  but expressing the *system axis* as a graph dimension rather than a single
  override key.
- **gen-algebra `foldLayers`** does `default<env<host<policy` settings
  precedence in pure Nix — **but only for value-layer cascade**, never as a
  replacement for `mkOverride`/`mkIf`/`type.merge` (H7).
- **gen-derive** decides *which* aspects/overlays/policies fire (deterministic
  override→priority→exclusive→additive, topo-sorted phases) — **C10, rule
  firing, not value merge.**
- **gen-bind `wrapAll`** hosts vanilla nixpkgs modules through the boundary
  without the arg-collision the module system would otherwise raise.
- The **terminal `evalModules`** is where the intrinsic, irreducible cost (H1,
  H7) is paid — once, per host, shared across all flake outputs that reference
  that host (C8).

**Why this is the right shape:** it inverts the naive "gen replaces the module
system" (H5) into "gen orchestrates *around* one preserved module system,"
banks the only measured win (H2 → the composition/multi-system axis), and never
pretends to cheapen the per-host merge it cannot cheapen (H7).

---

## 7. What `hola` is explicitly NOT

- **Not** a cheaper single-host `nixosSystem` evaluation. The per-host merge +
  submodule recursion (D, H7) is intrinsic; `hola` relocates and shares it, it
  does not shrink it.
- **Not** a cross-invocation cache. All memoization is intra-eval thunk sharing
  (H6); `nix build host-a` and `nix build host-b` in separate processes share
  nothing in pure Nix. (Out-of-language store/IFD caching is a *separate,
  later* axis, explicitly out of the pure-framework scope.)
- **Not** adios-grade per-module incrementality for vanilla nixpkgs. The sound
  free boundary is the submodule/per-host leaf (H3); per-module incrementality
  (C6) is available only for new `hola`-native edge-annotated modules.
- **Not** a `//`-storm fix. That bulk is nixpkgs import (H1).
- **Not** built on gen-schema/gen-aspects introspection in the hot path — those
  *add* module machinery (H5); they're definition-time only.

---

## 8. Open questions for Phase 2

Ordered by how much they move the design.

1. **C9 — collect-vs-merge split for `attrsOf (submodule)`.** The dominant
   real-config cost (D) is N independent `evalModules` per element. *Is the
   per-element cost dominated by re-collection (shareable) or by value-merge
   (intrinsic)?* This is **unmeasured** and decides whether a large per-host win
   exists at all. **Action:** `NIX_SHOW_STATS` partitioning of collect vs merge
   vs `evalOptionValue` on a real `systemd.services`-heavy host.
2. **C2 — store-hash parity.** Is a real nixpkgs host routed through
   `output-modules` + gen-bind **byte-identical** (`nix-diff` /
   `system.build.toplevel` drvPath) to plain `lib.nixosSystem`? This is a design
   *claim*, not yet verified (den v2 r2 open question). **Action:** build one
   real host both ways, diff the derivation.
3. **C3 — can real edges stay `config`-free?** Region partitioning only pays off
   if cross-region edges don't cross into `config` (else re-coupling, §5
   caveat). **Action:** audit a real fleet's cross-host references; classify how
   many are `config`-reads vs pure values.
4. **C1/C8 — quantify the prefix.** The multi-system win scales with the *size
   of the system-independent prefix*. **Action:** measure what fraction of a
   real flake's module/collect work is system-independent.
5. **Soundness guard for C1.** A shared region that silently reads the
   per-system input stales the share. **Action:** design a read-barrier /
   instrumented-proxy that *detects* an illegal system-input read at the graph
   boundary (runtime dependency capture, cf. H3 implementation-realism nuance).

---

## 9. Next analysis phase

**Phase 2 = empirical cost partition + parity proof.** Two workflows:

- **2a (measure):** instrument a real `systemd`-heavy `nixosSystem` and a real
  multi-system flake; partition `NIX_SHOW_STATS` into collect / merge /
  option-value / submodule-recursion; settle Q1 and Q4 with numbers. This
  converts the "~30 % on the composition axis, ~0 on the host axis" *estimate*
  into a *measured* per-component budget that tells us how big the C2+C1 prize
  actually is on the target workloads.
- **2b (prove):** prototype the C2 boundary minimally — one host, resolved on a
  gen-scope graph, crossing into one terminal `lib.nixosSystem` — and
  `nix-diff` it against the vanilla build (Q2). A green parity diff is the
  go/no-go gate for the whole `hola` thesis.

Only after 2a/2b do we design the engine proper (Phase 3) and the
edge-annotation contract for C6 (Phase 4).

---

*Generated from the `hoag-nixpkgs-feasibility` research workflow. All file:line
references are against `~/Documents/repos/{nixpkgs,adios,adios-flake,gen}` at the
revisions checked out 2026-06-23.*
