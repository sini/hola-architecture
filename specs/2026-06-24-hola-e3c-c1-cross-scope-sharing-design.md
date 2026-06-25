# hola Engine — E3c-C1: Complete-Sentinel-Proof Cross-Scope Eval-Result Sharing — Design Spec

> **Status:** approved design, **soundness-final after spec-review v1→v6**. **Soundness principle EARNED + the delta-enumeration class CLOSED — empirically verified on the vendored engine (v6: "could not break delta-enumeration soundness; no uncovered delta contribution exists; closed surface").** The delta surface is enumerated **structurally from `collectModules (delta)`** (imports-expanded, `pushDownProperties`) — superseding the name-set diff, which missed value-overrides of base-declared `_module.args` (`batteries/agenix.nix:87` `secrets`). v6 realization fixes folded: delta-leaf WHNF-forcing discipline + `tryEval`-fallback under the real per-element config; `collectModules`/`pushDownProperties` threaded into `share.nix`; the OFF/ON gate toggle. Pre-implementation (pending user review → writing-plans).
> **Date:** 2026-06-25.
> **Increment:** hola Phase 4.2, Wave C, **E3c-C1** (= PLAN.md Phase-4.5 L2 milestone C1). Follows E1/E2a/E2b (`github:sini/hola` `de5b21d`).
> **Repo:** `~/Documents/repos/hola`.
> **Reuses, UNCHANGED:** E1 engine (owns vendored `modules.nix` via `lib.extend`); E2b `runDenFleet`/`fleetEngineLib`; parity harness (`parity.drvPathGate`, `parity.force`). **Gen:** Stage A gen-free; Stage C (sibling) uses gen-graph for host topology only.

## 1. Context & motivation

E1→E2b proved hola owns `evalModules` **byte-identically vs nixpkgs**. E3c-C1 adds the first **cross-scope eval-result sharing**: evaluate a user-invariant home-manager base once, reuse across users on one host.

**Two complementary, both-required correctness layers.** (1) **Parity validation — `hola ≡ nixpkgs` — is a required correctness check** (E1–E2b, extended to the freeze via the 3-way gate `vanilla ≡ engine-OFF ≡ engine-ON`); we do **not** drop it. (2) **Intrinsic soundness — `hola-with-freeze ≡ hola-without-freeze`, by construction (§4)** — carries correctness when we run **only hola** (no vanilla to diff). The freeze stands on (2); (1) is the required regression check. The earlier error (parity gate *as the freeze's oracle*) is corrected.

**Perf framing (honest).** cortex's ~35s cold eval is ~94% intrinsic derivation construction; module-eval ~6% of wall. C1's standalone win is **modest**; the value is the proven mechanism + the cross-host foundation.

**Shareability — measured** (nix-config @ `8f84aa62`, users `sini`/`shuo`/`will`): G1 disjoint (`will` == base; `shuo` = base+3; `sini` = base+~245). The base reads a per-user value through one path — `modules/den/aspects/apps/shell/zsh.nix:28`, `programs.zsh.dotDir = "${config.xdg.configHome}/zsh"` (→ `home.homeDirectory` ← `home.username = mkDefault name`, the **substitutable** key arg). No structural `loc` reads in the base. The leak flows through `name` (sentinel-proven); the other ~24 aspects are invariant. No nix-config change.

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| C1-D1 | **Per-option (not whole-base).** | One `zsh.dotDir` per-user read trips a whole-base freeze ⇒ ~zero dedupe. |
| C1-D2 | **Own vendored `extendModules` (`modules.nix:380-393`) + the config assembly (`:279-302`); `modules.nix`-only, `types.nix` NOT vendored.** Base (`regularModules`) vs delta distinct at `:389`; base **HOISTED** to one eval. | `final.types` re-fixpoints onto the engine (E1); we own the config assembly so the freeze is *inside* it (§3), not a post-fixpoint overlay. |
| C1-D3 | **Correctness intrinsic, by a COMPLETE SENTINEL PROOF (§4): throw every per-element-VARYING input — the key via `_module.args.name` AND `prefix` (last element), plus the RESOLVED delta surface (args + option-defs the element carries beyond base) — and freeze only options forcing clean.** Empirically verified on the vendored engine. | The per-element-varying surface is **closed**: `{prefix (last element = key), modules (name-injection + delta contributions)}`. specialArgs is baked into `base` **once** (delta-independent, `types.nix:1393`), so it is invariant — thrown only defensively. Throws propagate through forcing ⇒ transitive dependence caught with no read-cone (verified, v3's hardest case). |
| C1-D4 | **Parity `hola ≡ nixpkgs` remains REQUIRED** (the 3-way gate, regression check, not the freeze's oracle). | We run only hola in production; the freeze's correctness is §4, but engine fidelity to nixpkgs is still required + validated. |
| C1-D5 | **Stage A gen-free; enable the freeze when `Δstats` net-negative, guard-OFF-by-default until then.** | The sentinel proof + owned re-merge need no graph/rebuilder; default-deny + exact fallback ⇒ guard-OFF is byte-identical. |
| C1-D6 | **cortex canonical, bitstream cross-check; staging A → C (Option 1); C scoped to Tier-1 intra-eval.** | Mirrors E2b; A is the reusable core. |

## 3. Mechanism (the spine — gen-free; all in the owned body + `lib/engine/share.nix`)

```nix
# lib/engine/vendor/modules.nix — owned extendModules (:380-393) + config assembly (:279-302). Helpers: lib/engine/share.nix.
# OUTER let (closes over regularModules :131 + evalModulesArgs :92; contains extendModules :380):
let
  referenceExtend = extendArgs: evalModules (evalModulesArgs // {      # the unmodified reference body (= :386-393)
    modules     = regularModules ++ (extendArgs.modules or []);
    specialArgs = (evalModulesArgs.specialArgs or {}) // (extendArgs.specialArgs or {});
    prefix      = extendArgs.prefix or evalModulesArgs.prefix or [];
  });
  # HOISTED, delta-INDEPENDENT key invariance — throw the element key in BOTH channels:
  keySentinel = evalModules (evalModulesArgs // {
    modules = regularModules ++ [ { _module.args.name = lib.mkForce (throw "KEY"); } ];   # NORMAL>mkOptionDefault, so it overrides submoduleWith's '‹name›'
    prefix  = (evalModulesArgs.prefix or []) ++ [ (throw "KEY") ];
  });
  valueBase  = referenceExtend { };                                   # concrete-placeholder base: source of frozen VALUES + the base option surface
  allOptions = share.optionPaths valueBase.options;                   # recursive attr-PATHS (lists) to every isOption leaf, _module-dropped; forces the options-tree SPINE, not opt.value
  K = share.keyInvariant { inherit keySentinel valueBase allOptions; };  # paths clean-under-key-throw ∧ function-free (over tryEval(force)) — computed ONCE
in
extendModules = extendArgs:
  let
    # DELTA SURFACE — enumerated STRUCTURALLY from the delta's own modules (NOT diffed against base):
    probe = builtins.tryEval (share.deltaConfigPaths {                # collectModules+pushDownProperties (threaded via the share.nix import, §9); union of config attr-PATHS the delta writes (incl. `_module.args.*`)
              modules = extendArgs.modules or [];
              config  = (referenceExtend extendArgs).config;          # delta leaves resolve against the REAL per-element config (no spurious throw); WHNF-forces the DELTA's own leaves (+ base options they read), never the frozen base values directly
            });
    deltaSentinel = evalModules (evalModulesArgs // {
      modules = regularModules ++ [ (share.throwAt probe.value) ];    # a module setting each delta path = mkForce (throw)
      prefix  = evalModulesArgs.prefix or [];
    });
    guardOK   = probe.success && share.structureStable valueBase extendArgs;   # enumeration clean ∧ delta declares no new option PATH ∧ same `_module.freeformType` (top-level sibling)
    frozenSet = if guardOK then share.refine K deltaSentinel else {}; # K paths clean under the delta sentinel; any enumeration throw ⇒ guardOK false ⇒ inert fallback (never a hard error)
  in
    if guardOK
    then share.spliceEval { inherit regularModules extendArgs valueBase frozenSet; }   # the owned config assembly, frozenSet-parameterized (below)
    else referenceExtend extendArgs;                                  # FALLBACK = the reference body, by construction
```

- **`deltaConfigPaths`** (the v5 fix) enumerates the delta's contribution by **what it writes**, not by diffing names/values against base: `collectModules` over `extendArgs.modules` (the owned import-expansion machinery — catches `imports`/`mkMerge`), then `pushDownProperties` and the union of recursive `config` attr-paths each collected module sets, including `config._module.args.<n>`. It catches a delta that *overrides* a base-declared `_module.args` value (the name-set diff missed it — `batteries/agenix.nix:87` `secrets`). **Forcing discipline (corrected v6):** recursive leaf-enumeration WHNF-forces each *delta* leaf (`isAttrs` decides leaf-vs-recurse) — never `deepSeq`, never `mkIf`/`mkMerge` conditions (the `_type` wrapper stops the walk), and never the frozen *base* values directly (only base options a delta leaf reads). It is applied under the **real per-element `config`** so delta leaves resolve as in the actual eval, and the whole probe is wrapped in `tryEval`: any throw ⇒ `guardOK=false` ⇒ inert `referenceExtend` fallback — loud, gated, never a silently-wrong frozen set. **Over-approximation:** `pushDownProperties` truncates `mkIf`/`mkOverride`-wrapped subtrees at the wrapper boundary (the parent path), so throwing that parent conservatively poisons the whole subtree (sound — over-throwing only shrinks `frozenSet`; a dedupe cost on configs with `mkIf`-wrapped nested groups, not a correctness cost). `name` (the key) is already thrown by `keySentinel`.
- **`spliceEval`** runs the **owned** per-element `evalModules`, but its config assembly (`modules.nix:283`) is parameterized over **option-path** membership: `declaredConfig = mapAttrsRecursiveCond (v: !isOption v) (path: opt: if path ∈ frozenSet then (getAttrFromPath path valueBase.config) else opt.value) options` — `path` is the full recursive list-path `mapAttrsRecursiveCond` supplies (e.g. `["programs" "zsh" "dotDir"]`), matched against `frozenSet` (also list-paths). For a frozen option it serves `valueBase`'s value and — **by laziness — never forces that option's per-element merge** (the dedupe); the rest force normal `opt.value`. Returns the result attrset (`:399-404`) unchanged except this substitution. **`frozenSet = {}` ⇒ byte-identical to `referenceExtend` by construction** (every `opt.value` normal) — the reassembly invariant the gate asserts (C1-A1).
- **`structureStable`** = `attrNames elem.options ⊆ attrNames valueBase.options` (delta declares no new top-level option) ∧ `valueBase._module.freeformType == elem._module.freeformType` — the **top-level `_module` sibling** on the result (`_module` is `removeAttrs`'d from `result.config`, `:402`, so `config._module` throws), matching nixpkgs `submoduleWith` (`types.nix:1418`). Post-eval `options`-surface reads (cheap; avoids the let-local `declsByName`). Else fall back. (`elem` here is `referenceExtend extendArgs`'s option surface only — its frozen config values are never forced.)
- **Fallback** = `referenceExtend extendArgs` ⇒ the mechanism cannot ship wrong, only inert.

## 4. Soundness — a complete sentinel proof (intrinsic, hola-only; empirically verified on the vendored engine)

An option `O` is frozen iff `O` is per-element-invariant, **proven** by forcing it under a sentinel that throws **every** per-element-VARYING input. `extendModules` is the only per-element re-entry; in the real `attrsOf (submoduleWith …)`, `submoduleWith.merge.v2` calls `base.extendModules { modules = [{_module.args.name = last loc;}] ++ defs; prefix = loc; }` (`types.nix:1449-1455`) with **specialArgs baked into `base` once** (`:1393`) and **not passed per-element** at this call site (so it is delta-independent here — note the *generic* `extendModules` at `modules.nix:390` *does* merge `extendArgs.specialArgs`; the invariance is a property of the real `submoduleWith` re-entry, not of `extendModules` in general, and a `throwAt`-style specialArgs guard is added defensively). So the per-element-varying surface is **closed**: the **key** (as `_module.args.name` AND the last `prefix` element, since `loc = prefix ++ [name]`, `modules.nix:877`) and the **delta** (everything its modules write). The sentinel throws all of it:

- **key**: `_module.args.name = mkForce (throw)` AND `prefix = … ++ [throw]` (hoisted, delta-independent);
- **delta**: the surface enumerated **structurally from `collectModules (extendArgs.modules)`** (imports-expanded) — the union of every `config` attr-path the delta's modules write, including `config._module.args.<n>`, thrown via `mkForce`. This is what the delta *contributes* (not a diff against base), so it catches additions, `imports`/`mkMerge`, **and value-overrides of a base-declared `_module.args`** (which a name-set diff missed — `batteries/agenix.nix:87` `secrets`). Enumeration WHNF-forces each *delta* leaf (never base values, never `mkIf` conditions — §3); a thrown delta leaf is loud and gated (`tryEval` ⇒ fallback), never a silently-wrong frozen set.

Force each candidate (with the function-content walk). **Clean ⇒ `O` reads no per-element-varying input through any channel — config-read, module-arg (`applyModuleArgs:707-731` resolves `config._module.args` regardless of injection path), or structural `prefix`/`loc` — directly or transitively** (a throw in a dependency propagates through forcing). A proof, not a sample. The realization risk is *under-throwing* the delta; enumerating the delta's *written* paths via `collectModules` (rather than approximating by name/shape diff) is what makes the enumeration complete.

**Empirically verified** (vendored engine; re-run in v4):

| Case | Construction | Result |
|---|---|---|
| 1 | normal option, throwing `prefix` | **clean** — sentinel doesn't break eval (`prefix==[]` length short-circuit, `:158`) |
| 2 | option reads its `loc` (`dovecot.nix:302`) | **throws** — caught |
| 3 | option reads `name` | **throws** — caught |
| 4 | `O`→`D`→`loc`, `O` has no syntactic `.loc` (v3's hardest) | **throws** — by propagation, **no read-cone** |
| 5 | genuinely pure option | **clean** — frozen |
| + | real `zsh.dotDir`/`username` (name-derived) vs `editor` (invariant) | dotDir/username **throw+remerge**; editor **freezes** |

**Hoist boundary.** The **key sentinel** is delta-independent ⇒ `K` is computed **once**. The **delta sentinel** (resolved surface) is per-element ⇒ `frozenSet(element) = K ∖ {throws under this delta}`. A `K` member can become per-element-varying *only* through a delta channel, which the delta sentinel catches (verified). Empty delta (`will`) ⇒ `frozenSet = K`.

**`spliceEval`'s "frozen never observes remerged" is sound, not circular.** A remerged option is per-element-varying (delta-touched, or reads `loc`/`name`). A frozen option is sentinel-clean — forcing it does not throw — so it cannot read any per-element-varying option (it would force that option's thrown input → excluded). Frozen options read only frozen constants; remerged options may read frozen constants (correct). One-directional.

**Function-content rejection.** `deepSeq` does not enter lambda bodies (verified: depth-4 closures survive), so a clean value may *contain* a closure capturing a per-element input. The `keyInvariant` predicate is `tryEval (force candidate)` **succeeds** ∧ the **forced** value tree is function-free (a structural walk `isAttrs→mapAttrs / isList→map / isFunction→reject`, over the already-forced `tryEval` value — not `toJSON`, which throws uncatchably on functions, nor `==` alone).

**Transition-validation (required).** The nixpkgs-parity `drvPathGate` (`vanilla ≡ engine-OFF ≡ engine-ON`) is a **required** regression check that hola+freeze is byte-identical to nixpkgs — not the freeze's soundness argument (§4 is), and a dev/validation-time comparison (production runs only hola), but `hola ≡ nixpkgs` is a held, required correctness requirement.

## 5. Coverage / gen consumption

`genExpansionNeeded = none`. **Stage A is hola-internal end-to-end.** Helpers in `lib/engine/share.nix` (hola-authored, **outside** the vendor-integrity surface — `vendor-check` diffs only `vendor/modules.nix`), each with a pinned contract:
- **`optionPaths opts`** → recursive list of attr-paths (lists) to every `isOption` leaf, `_module`-dropped (`builtins.filter (n: n != "_module")` inline — `parity.dropModule` is let-local, not exported); forces the options-tree spine, not `opt.value`.
- **`keyInvariant {keySentinel, valueBase, allOptions}`** → the subset of `allOptions` whose `keySentinel` value `tryEval(force)`s clean ∧ whose `valueBase` value is function-free (structural `isFunction`-walk over the **forced `tryEval`** tree: `isAttrs→mapAttrs / isList→map / isFunction→reject`).
- **`deltaConfigPaths { modules, config }`** → `collectModules` (owned, `:261/:414`) over `modules` (imports-expanded; `class`/`modulesPath`/`args` from the owned eval context, `args` carrying the passed-in real per-element `config`), then `pushDownProperties` (`:1335`) each module's `config`, union of the recursive leaf attr-paths (incl. `_module.args.*`). **WHNF-forces each delta leaf** (`isAttrs` leaf-test) — never `mkIf`/`mkMerge` conditions (the `_type` tag stops the walk), never frozen base values; **over-approximates** at property-wrapper boundaries (parent path, regardless of condition — only shrinks the frozen set, never unsound). `collectModules`/`pushDownProperties` are top-level lets in the owned body, **threaded into `share.nix` via the import** (§9), not the deprecation-warned `private` alias. The `extendModules` call wraps this in `tryEval` ⇒ inert fallback on any throw.
- **`throwAt paths`** → a module whose `config` sets each path to `mkForce (throw …)`.
- **`refine K deltaSentinel`** → `K` paths whose `deltaSentinel` value `tryEval(force)`s clean.
- **`structureStable valueBase extendArgs`** → `attrNames (referenceExtend extendArgs).options ⊆ attrNames valueBase.options` ∧ `valueBase._module.freeformType == (referenceExtend extendArgs)._module.freeformType` (top-level sibling; options-surface only, never frozen values).
- **`spliceEval {regularModules, extendArgs, valueBase, frozenSet}`** → the owned per-element `evalModules` with the `:283` `declaredConfig` callback substituting `getAttrFromPath path valueBase.config` for `path ∈ frozenSet`.

Derivations avoid the let-local `declsByName`/`pushedDownDefinitionsByName` (`:789/:831`, confirmed not exported). No gen-graph / gen-rebuild in Stage A.

## 6. Validation gate & measurement

**Required parity gate (`ci/tests/e3c-c1-parity.nix`, `cd ci && nix flake check`):** 3-way `drvPathGate`
`vanilla(runDenFleet (l:l)) ≡ engine-share-OFF(guard forced false) ≡ engine-share-ON(guard enabled)` — the OFF/ON toggle is a `mkEngine { shareEnabled ? false }` flag threaded into `guardOK` (`guardOK = shareEnabled && probe.success && structureStable …`); the gate builds two engine libs (`shareEnabled` false/true), keeping guard-OFF-by-default (C1-D5) byte-identical
across `config.system.build.toplevel.drvPath` **and** each configured user's `config.home-manager.users.<u>.home.activationPackage.drvPath` — **assert all of sini/shuo/will explicitly** (do not rely on toplevel transitively covering an unreferenced user) — on **cortex** + a **bitstream** cross-check. (`parity.drvPathGate` is hard-wired to `system.build.toplevel.drvPath` `:93-94`; the parameterized per-user accessor lands in C1-A1.) **Reassembly-faithfulness:** C1-A1 asserts the **empty-frozen** splice (`frozenSet={}`, `guardOK=true`) drvPath `==` `referenceExtend` drvPath (toplevel + per-user) — isolating the reassembly path from any freeze. **referenceExtend faithfulness** to the original `:386-393` body is carried by the gate's `vanilla ≡ engine-OFF` arm (engine-OFF dispatches to `referenceExtend`); optionally a one-time check that `referenceExtend` drvPath `==` pristine `extendModules` drvPath before the edit.

**Dedupe (`ci/bench`, never gates):** a **new** fleet-tier `NIX_SHOW_STATS`-over-drvPath bench (current `stat-capture` is value-tier-only) emits `ΔnrThunks`/`ΔgcTotalBytes`/`ΔcpuTime` across `{identity, share-OFF, share-ON}` + per-user share/fallback counts. **Enable rule (C1-D5):** flip ON iff `Δstats` net-negative.

## 7. What it proves / honest unknowns / out of scope

**Proves:** intrinsically-sound (complete sentinel proof, empirically verified on the vendored engine), per-option cross-scope sharing on a real fleet host, validated byte-identical to nixpkgs.

**Honest unknowns:** (a) realized dedupe **modest**, unmeasured in bytes. (b) **Cost:** ~1 hoisted key-sentinel eval + `valueBase` (shared) + per-element {`collectModules (delta)` + config-path walk (WHNF-forces the delta's own leaves + base options they read, not the frozen base values) + `deltaSentinel` re-force of the `K` subset + per-element merge of `remergeSet`}; frozen options' merges are skipped by laziness — a win for `N ≥ 3` if `K` is substantial; `stat-capture` measures it. (c) `structureStable` falls back on structural deltas (frequency unmeasured; G1-disjoint config-only deltas pass).

**Out of scope:** transitive read-cone (**refuted** — throw-propagation suffices, verified); cross-host C2 / inter-eval persistence (sibling/future); no nix-config change.

## 8. Increments (each parity-validated; A delivers per-option dedupe)

- **C1-A1 — hoist + scaffold + gate.** HOIST (`valueBase`/`keySentinel`/`referenceExtend` at the outer let; acceptance: one base thunk forced once across N elements); the **empty-frozen** splice (`frozenSet={}`) **asserted drvPath-`==` `referenceExtend`** (toplevel + per-user) — reassembly faithfulness before any freeze; the parameterized 3-way `drvPathGate` (toplevel + all three users) on cortex + bitstream. **No gen.**
- **C1-A2 — the complete-sentinel partition (the dedupe).** `share.nix`: key sentinel → `K`; **structural** delta sentinel (`collectModules` → `deltaPaths` → `throwAt`) → `frozenSet`; `structureStable`; `isFunction`-walk; `spliceEval`. **Property tests (each MUST re-merge):** `loc`-dependent base option; transitive `O`→`D`→`loc`; per-element `_module.arg` reader injected via **`imports`** (not just direct); a delta that **overrides a base-declared `_module.arg` value** (name-stable — the v5 counterexample); a `home.packages`-style delta-appended option a base option reads; a nested-closure value; a **plain (unwrapped) config-reading delta leaf** (the `tryEval`-fallback path). **7th case (integration, beyond the 6 property tests):** a real `types.attrsOf (types.submoduleWith {…})` with a name/loc-reading submodule — confirm the synthetic key sentinel at the submodule's `evalModulesArgs` throws iff the option reads name/loc, matching the real `attrsOf` path. **No gen.**
- **C1-A3 — measure + enable.** Fleet-tier `Δstats`; flip ON iff net-negative.

## 9. Components / files

| File | Status | Role |
|---|---|---|
| `lib/engine/vendor/modules.nix` | edit | `extendModules` HOIST + guarded fast path + `referenceExtend` + the `mkEngine { shareEnabled }` flag into `guardOK`; the config assembly (`:283`) gains the `frozenSet`-parameterized substitution (`spliceEval`); import `share = import ../share.nix { inherit lib collectModules pushDownProperties; }` at the top-level let site (where both internals are in scope, unwrapped — not the deprecation-warned `private` alias). Vendor-integrity → bounded diff excluding the E3 hunk. |
| `lib/engine/share.nix` | new | Outside the vendor surface: the §4 sentinel construction (`collectModules`-based `deltaConfigPaths` + `throwAt`), `keyInvariant`/`refine`, `structureStable`, `isFunction`-walk, `optionPaths`, the `spliceEval` glue. |
| `lib/parity.nix` | edit | Parameterized `drvPathGate` accessor (per-user `home.activationPackage.drvPath`, all configured users). |
| `ci/tests/e3c-c1-parity.nix` | new | 3-way required gate (cortex + bitstream) + the empty-frozen reassembly assertion. |
| `ci/tests/den-fleet-parity.nix` | edit | Rewrite `channel-modules-identity` (`readFile ==`, `:47-55`) to a bounded diff excluding the documented E3 hunk. |
| `ci/bench/*` | new | Fleet-tier `NIX_SHOW_STATS`-over-drvPath bench. |

No `ci/flake.nix` input changes (gen-free).

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Under-throwing the delta** (a delta contribution missed ⇒ wrongly frozen). | Enumerate the thrown set from `collectModules (delta)`'s **written config-paths** (catches additions, `imports`/`mkMerge`, AND value-overrides of base-declared args — the v4/v5 failures), not a name/shape diff; property-test imports-injection, a delta-appended option, AND a base-arg value-override. Guard-OFF + the required 3-way gate (all users) are the independent backstop: an over-freeze surfaces as a per-user drvPath diff and is never enabled. |
| **A per-element channel beyond the closed surface.** | The surface `{prefix, modules}` is closed (specialArgs baked into base, invariant); survived ~15 adversarial probes on the vendored engine; the required parity gate is the independent backstop. |
| **`spliceEval` reassembly diverges** from `referenceExtend`. | C1-A1 asserts empty-frozen drvPath `==` `referenceExtend` (toplevel + per-user) before any freeze; `frozenSet={}` reduces to it by construction. |
| **Frozen value contains a closure.** | `isFunction`-walk over the forced `tryEval` value tree (verified necessary). |
| **`structureStable` mis-scoped.** | Conservative (`attrNames` ⊆ + freeformType) ⇒ only over-falls-back, never over-admits; property-test a declaration-adding delta ⇒ fallback. |
| **Throwing `prefix`/`name` perturbs some uncovered module.** | A2 re-runs the 6-case verification against the vendored engine + a real cortex base before enabling; guard-OFF + the parity gate catch any perturbation as a drvPath diff. |
| **Win negligible.** | C1-D5 guard-OFF-by-default; the proven mechanism + C foundation stand regardless. |

## 11. References

- Engine substrate: `specs/2026-06-24-hola-engine-{e1,e2b}-*.md`, `specs/2026-06-23-parity-harness-design.md`.
- Perf floor: `analysis/experiments/cortex-profile/cortex-profile.md` (~35s, ~94%, ~6%).
- Spec-review v1→v4 drivers + the empirical refutations: module-arg (`applyModuleArgs:707-731`); prefix/loc (`loc = prefix ++ [name]`, `modules.nix:877`; `dovecot.nix:302`); nested-function laziness; two-probe 2-sample defeat; imports-injected-arg under-throw. **Empirics:** `/tmp/loc_sentinel_test.nix`, `/tmp/loc_transitive_test.nix` (5 cases, vendored-engine-reproduced).
- Source anchors: `lib/engine/vendor/modules.nix` (`:158` prefix length short-circuit, `:279-302` config assembly, `:283` declaredConfig, `:380-393` extendModules, `:386-393` reference body, `:389` base/delta, `:399-404` result shape, `:707-731` applyModuleArgs, `:877` loc, `:789/:831` let-local byName, `:1185` mergeDefinitions, `:1418` `base._module.freeformType`, `:261/:414` collectModules); nixpkgs `types.nix:1393` (base bakes specialArgs), `:1449-1455` (v2 per-element call); `lib/parity.nix:14`/`:90-107`; nix-config `modules/den/aspects/apps/shell/zsh.nix:28`, `batteries/agenix.nix:87`.
- Memory: `project_hola`, `project_gen_rebuild`, `project_claim_provide_engine`.
