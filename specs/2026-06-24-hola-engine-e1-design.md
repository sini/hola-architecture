# hola Engine — E1: Byte-Identical Hosted-Merge Owning `modules.nix` — Design Spec

> **Status:** approved design, pre-implementation (pending spec-review loop + user review).
> **Date:** 2026-06-24.
> **Increment:** hola Phase 4.2, Wave C, sub-increment **E1** (first of E1→E2→E3).
> **Repo:** `~/Documents/repos/hola` (`github:sini/hola`), on top of the shipped parity harness.
> **Foundation:** parity harness (the executable contract) + gen-rebuild v2 (main @ 97c9af3);
> E1 consumes **only** the harness — no gen-rebuild wiring yet (that is E3).
> **nixpkgs rev for all line citations:** `567a49d1913ce81ac6e9582e3553dd90a955875f`
> (`nixos-unstable`, the harness's pinned `nixpkgs` input; line numbers are rev-sensitive and
> must be re-verified on a nixpkgs bump — same K9 discipline as the vendored copy).

## 1. Context & motivation

Wave C is the **engine arm**: a lib-shaped `{ lib; evalModules }` drop-in that hosts
*unmodified* nixpkgs/NixOS modules, slots into `adapter.engines.engine` (the seam is
already there, proven ready by injection), and proves `vanilla == engine` byte-identical
through the existing parity harness. Den integration, cross-scope sharing, and the zen
comparison all gate on the engine being byte-identical.

The engine ships in three parity-gated sub-increments:

- **E1 (this spec)** — the minimal drop-in that **owns the `evalModules` body** and hosts
  `lib.types` merge verbatim, with **no selection**. Gate: `valueEq`/`drvEq`/`expectThrowFx`
  `engine == vanilla` on the existing corpus (synthetic / hc3 landmines / real-host drvPath).
- **E2** — Den-as-corpus: byte-identical on real, unmodified Den configs at scale.
- **E3** — external lazy selection from the HOAG graph + gen-rebuild incremental override,
  swapped **inside** the owned body, each step parity-gated against the E1 baseline.

E1 is the load-bearing proof: **a separately-owned engine body that is still byte-identical.**
Its value is *not* wall-time (the cortex pivot settled that single-host eval is ~94% intrinsic
derivation construction). Its value is establishing the **ownership seam** — being
`lib.modules.evalModules` at *every* recursion level — which is the prerequisite for E3's
selection/incrementality and the only thing the harness's `identity` engine structurally cannot
do (HC5).

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| E1-D1 | **Vendor-and-own-the-seam**, *not* a from-scratch orchestration rewrite, *not* graph-native now | Owning the recursion seam (HC5) is the novel/risky part; the body's *content* is not. Verbatim vendor makes byte-identity near-tautological **by design**, isolating the seam as the single variable under test. From-scratch and graph-native both fight byte-identity with **no baseline to bisect against** (see §9). The vendored body is **not throwaway** — it is the permanent host substrate E3 edits in place. |
| E1-D2 | **Own the body by `lib.extend` overriding `final.modules`** with a vendored `modules.nix` imported against `final` | `lib/default.nix:474` re-exports the entire module surface via `inherit (self.modules)`, so overriding `final.modules` propagates `evalModules`/`mkIf`/`mkMerge`/`mkOverride`/`filterOverrides`/… through the fixpoint. `final.types` is re-fixpointed against `final`, so `submoduleWith` reaches the vendored `evalModules` at `base`; the vendored file-local `extendModules` keeps every submodule re-entry inside the owned body (§3). |
| E1-D3 | **Host `lib.types` + `type.merge` verbatim, *by reference*** — no hola merge code, and `types.nix` is **not** vendored in E1 | HC3: the merge kernel is value-shape-dispatched, mutually recursive with `evalModules` (`submoduleWith.merge → base.extendModules → evalModules`), positional for same-priority merge, and throws. E1 swaps **only** `modules.nix`; `final.types` is the **live** outer-lib `types.nix` re-fixpointed against `final` (so it reaches the vendored `evalModules` at `base` — §3.2 — while the merge *code* stays unmodified/un-owned). "Verbatim" = unmodified, not copied. **E3 implication:** if E3 needs to alter merge behavior it must *also* vendor `types.nix`; until then `type.merge` is hosted by-reference. |
| E1-D4 | **Commit the vendored copy into the repo**, isolated under `lib/engine/vendor/` with its MIT `COPYING` + provenance `README` | True ownership + a file E3 can edit; honor nixpkgs' MIT license (attribution). Generating it at eval time would leave nothing to own/edit and would silently track upstream. |
| E1-D5 | **Vendor from the corpus's *actual* nixpkgs input** (rev `567a49d`), byte-for-byte | The corpus's `vanilla` lib is `import ../. { lib = nixpkgs.lib; }` where `nixpkgs` is the ci flake's `outputs` input = `root.inputs.nixpkgs` = flake.lock node **`nixpkgs_7`** = rev `567a49d` (= store `z1mj0970…`). **Disambiguation (a reviewer tripped on this):** the lock *also* contains a node literally named `nixpkgs` (= `64c08a7`) which is a **transitive/gen** nixpkgs and is **not** what the corpus evaluates against — never key off `l.nodes.nixpkgs`. Vendoring 567a49d makes the vendored copy `== ${nixpkgs}/lib/modules.nix`, so `vendor-check` (§7) passes and `vanilla == engine`. A nixpkgs bump without re-vendoring is exactly the K9 migration `vendor-check` flags. |
| E1-D6 | **Engine-parity is a new `compose.engineParity` + a gating `ci/tests/engine-parity.nix`**, plus a **non-vacuity probe** | Mirror the harness's proven `selfParity` shape (swap `identity`→`engine`); the probe (perturb the vendored copy → assert `engineParity` flips `false`) proves the gate bites on the *engine*, exactly as the harness's break-test proved `selfParity` non-vacuous. |
| E1-D7 | **No `_prev` use in the overlay; override `modules` only** (not `evalModules` too) | Minimal, idiomatic: the top-level `evalModules` re-export already resolves to `final.modules.evalModules` through the fixpoint. Belt-and-suspenders double-override is redundant. |

## 3. The ownership mechanism (the spine)

### 3.1 Construction

```nix
# hola/lib/engine/default.nix
{ lib }:
let
  holaLib = lib.extend (
    final: _prev: {
      modules = import ./vendor/modules.nix { lib = final; };
    }
  );
in
{
  lib = holaLib;
  evalModules = holaLib.evalModules;
}
```

### 3.2 Why this owns *every* recursion level

`lib.extend f rattrs` (`lib/default.nix:40`) computes `super = rattrs final` then
`final = super // f final super`. Because the original lib body does
`modules = import ./modules.nix { lib = self }` and `types = import ./types.nix { lib = self }`
with `self = final` (`callLibs`, `lib/default.nix:48,71,73`):

1. **Top-level eval** — `holaLib.evalModules` is `inherit (self.modules) evalModules`
   (`lib/default.nix:474`) = `final.modules.evalModules` = the vendored `evalModules`. ✓
2. **Submodule `base`** — `final.types` is re-imported against `final`, and
   `submoduleWith` does `inherit (lib.modules) evalModules` (`types.nix:1375`) →
   `final.modules.evalModules` = vendored. So `base = evalModules {…}` (`types.nix:1393`) is
   built by hola. ✓
3. **Per-element value merge** — the submodule's value comes from `base.extendModules`
   (`types.nix:1452`, `merge.v2`), and `extendModules` (`modules.nix:386`) calls the
   **file-local** `evalModules` (`modules.nix:92`). Since `base` was built by the vendored
   body, that file-local recursion is hola's. So every `attrsOf submodule` element, and
   `getSubOptions`/`description` (also via `base.extendModules`), stays inside the owned body. ✓
4. **mk\* surface** — `mkIf`/`mkMerge`/`mkOverride`/`mkForce`/`mkOrder`/`filterOverrides`/
   `mergeModules`/… are all `inherit (self.modules)` (`lib/default.nix:474`), so a module's
   `lib.mkForce` (threaded as `final` via eval-config / specialArgs) resolves to the vendored
   copy too. ✓

This is precisely the HC5 gap the harness's `identity` engine cannot close: its thin
`a: prev.modules.evalModules a` wrapper is reached at the outer eval and the first
submodule `base`, but `base.extendModules` re-enters the **unwrapped original**. The vendored
body, being the file-local `evalModules` of `base`, owns the re-entries.

### 3.3 Cross-lib mk\* interop (a parity-relevant invariant)

Corpus/Den modules are authored with the **outer** lib's `mkForce`/`mkOverride` (the test's
`nixpkgs.lib`). The engine consumes those markers and merges them with the **vendored**
`filterOverrides`/priority logic. Verbatim vendor ⇒ identical `_type = "override"` strings and
identical priority integers ⇒ identical merge. (Worth stating because it is the one place two
different lib instances meet inside one eval.)

### 3.4 Self-contained vendoring (verified)

`modules.nix` @ `567a49d` is `{ lib }:`-shaped, pulls every helper incl. `types` via
`inherit (lib)` (`modules.nix:4-58`), and has **zero live relative imports** — the sole
`./module.nix` (`modules.nix:2100`) is inside a doc-comment Example; `importApply`
(`:2111`) takes the path as a runtime argument. A byte-for-byte copy with `{ lib }` is
self-contained. `types.nix` has no relative imports either. No path fixups required.

The only self-referential string is `internalModule._file = "lib/modules.nix"`
(`modules.nix:141`) — a **literal**, so relocation does not change it. Module `_file`/position
data derives from the *config* modules (the corpus), not from `modules.nix`'s own path, so
vendoring is position-stable in all gated outputs.

## 4. What the proof establishes (honest scope)

Because the vendored body is verbatim, `engine` is *functionally* nixpkgs relocated and
re-fixpointed; `vanilla == engine` is near-tautological **by construction**. That is deliberate
single-variable isolation, not a weakness. E1 **proves**:

- the lib-splice + full recursion-ownership wiring (incl. `submoduleWith → base →
  base.extendModules`) is byte-identical end-to-end, including the real-host
  `system.build.toplevel.drvPath` tier;
- cross-lib mk\* interop (§3.3) is byte-identical.

E1 **does not** prove that a *modified* orchestration is byte-identical — that is E3's job,
gated incrementally against this exact baseline. Holding the body constant is what makes E3's
later diffs attributable.

## 5. Components / files

| File | Status | Role |
|---|---|---|
| `lib/engine/vendor/modules.nix` | **new (vendored)** | Byte-for-byte copy of nixpkgs `lib/modules.nix` @ `567a49d`. |
| `lib/engine/vendor/COPYING` | **new** | nixpkgs MIT license (© 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors). |
| `lib/engine/vendor/README.md` | **new** | Provenance: source rev, "vendored verbatim; bumps are a parity-gated K9 migration", pointer to `vendor-check`. |
| `lib/engine/default.nix` | **new** | The `lib.extend` constructor + `{ lib; evalModules }` record (§3.1). |
| `lib/adapter.nix` | **edit** | Replace the `# engine = …` placeholder (`adapter.nix:26`, whose comment shows the inline `{ lib = holaLib; evalModules = holaLib.evalModules; }`) with `engine = import ./engine { inherit lib; };` — `lib/engine/default.nix` returns exactly that record, so the two forms are equivalent. |
| `lib/compose.nix` | **edit** | Add `engineParity = fx: …` — `vanilla` vs `engine` across value/drvPath/throws gates (mirror of `selfParity`). |
| `ci/tests/engine-parity.nix` | **new** | `engineParity` over the full corpus (synthetic, 4 hc3 landmines, real-host drvPath) + the non-vacuity probe. Gate = all `true`. |
| `ci/apps.nix` | **edit** | Add the non-gating `vendor-check` Tier-2 evidence app (§7). |

`lib/types` / `type.merge` have **no hola file and are not vendored in E1** — they are hosted
**by-reference**: the live outer-lib `types.nix`, re-fixpointed against `final` so it reaches the
vendored `evalModules` at submodule `base` (§3.2). "Verbatim" means unmodified, not copied.
(E3 vendors `types.nix` only if it must alter merge behavior.)

## 6. Testing & the gate

- **`ci/tests/engine-parity.nix`** (gating, via `cd ci && nix flake check` — the authoritative
  gate; `nix-unit --flake` under-reports, do not use): for each corpus fixture,
  `compose.engineParity fx == true`, dispatching on `fx.gate` (`value` → `valueEq`,
  `drvPath` → `drvEq`, `throws` → `expectThrowFx` both engines) exactly as `selfParity` does.
  Fixtures: `synthetic`, `priorityFold`, `order`, `valueMeta` (the reverse-`listOf` quirk),
  `latticeThrows`, `realHost` (drvPath, `n = 3`).
  - **Throws-gate caveat (faithful to the harness):** `expectThrowFx` asserts *that* both engines
    throw, not that the error *messages* are identical (`compose.nix:26`). For verbatim E1 the
    message is identical by construction (same code throws the same string), so message-identity
    holds for `latticeThrows` even though the gate does not separately assert it. Don't over-claim
    message-tier identity from a passing throws gate; tightening it is a later option, not an E1 need.
- **Non-vacuity probe** (gating): construct a deliberately-perturbed engine from a copy of the
  vendored body with one quirk flipped (e.g. drop the `reverseList` that produces the
  same-priority same-order `listOf` reverse order), and assert `engineParity` over `valueMeta`
  is **`false`**. Proves the gate distinguishes a wrong engine — the engine analogue of the
  harness's `selfParity` break-test.

## 7. K9 / provenance / license

- `vendor/README.md` records the exact source rev and states the migration rule: **bumping the
  harness's nixpkgs requires re-vendoring `modules.nix` and re-running the parity gate.**
- `vendor/COPYING` reproduces nixpkgs' MIT text with attribution (honor the license).
- **`nix run ci#vendor-check`** (Tier-2, non-gating, via the `extraModules` seam): diffs
  `lib/engine/vendor/modules.nix` against `${nixpkgs}/lib/modules.nix`, where `${nixpkgs}` is the
  **resolved `outputs` input** (`nixpkgs.outPath`, already threaded as a specialArg), **not** a
  rev string off a lock node — this is robust against the multi-`nixpkgs`-node lock (E1-D5) and
  works whatever node key the lock assigns. **Byte-identical at E1**; once E3 edits the body it
  reports "diverges in these documented ways." Surfaces silent upstream drift without gating CI on
  an external moving target. A tiny gating companion assertion (`vendored == ${nixpkgs}/lib/modules.nix`
  at E1) may live in `engine-parity.nix` to enforce the K9 rule mechanically while the body is verbatim.

## 8. Out of scope (explicit — no scope creep)

No module selection, no gen-graph / gen-scope / gen-rebuild wiring, no D-hoist / shape-memo,
no Den corpus, no perf claim. E2 = Den-as-corpus on this same body; E3 = selection +
incremental override swapped inside the owned body. Determinate / wall-time is the separate
opportunistic evaluator track (cortex pivot), untouched here.

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Tautology critique** — "verbatim vendor proves nothing." | Reframed as single-variable isolation (§4) + the non-vacuity probe (§6) proves the gate bites; the *seam* (HC5 ownership of `base.extendModules` re-entries) is the non-trivial thing under test, and `identity` demonstrably cannot achieve it. |
| **nixpkgs drift** — bump changes `modules.nix`, vendored copy stale. | `vendor-check` (§7) flags it; K9 migration rule documented (E1-D5). E1 byte-identity is pinned to one rev. |
| **Hidden lib re-export bypass** — something captures the original `evalModules` outside `self.modules`. | Verified: within `lib`, `evalModules` is referenced only via `self.modules` (`default.nix:474`) and `lib.modules` (`types.nix:1375`); `modules.nix`'s internal recursion is file-local. No bypass path. |
| **Position/`_file` sensitivity** from relocation. | Verified position-stable (§3.4): the only self-referential string is a literal; user-module `_file` derives from config modules. |
| **`lib.extend` cost** — full lib re-fixpoint per engine. | One-time, negligible; not on any gated value/drvPath output. |

## 10. References

- Parity-harness contract: `specs/2026-06-23-parity-harness-design.md`; impl in
  `~/Documents/repos/hola/lib/{parity,adapter,compose,corpus}.nix`.
- Engine constraints K1–K9 / HC1–HC7: `analysis/phase-2-implementation-seed.md`.
- Verified claims H1–H7: `analysis/phase-1-feasibility.md`.
- nixpkgs @ `567a49d`: `lib/modules.nix` (`:92` evalModules, `:386` extendModules,
  `:474`→ default.nix re-export, `:1452` types merge), `lib/types.nix` (`:1366` submoduleWith,
  `:1375` `inherit (lib.modules) evalModules`, `:1393` base), `lib/default.nix` (`:40` extend,
  `:48` callLibs, `:474` re-export).
- Wave-C session prompt: `WAVE-C-ENGINE-SESSION.md`.
- Memory: `project_hola`, `project_gen_rebuild`, `project_zen_vic`.
