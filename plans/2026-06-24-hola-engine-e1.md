# hola Engine E1 — Byte-Identical Hosted-Merge — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if
> subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the hola engine arm — a lib-shaped `{ lib; evalModules }` drop-in that *owns* the
`evalModules` body (vendored verbatim) and proves `vanilla == engine` byte-identical through the
existing parity harness.

**Architecture:** `lib.extend (final: _prev: { modules = import ./vendor/modules.nix { lib = final; }; })`.
Overriding `final.modules` alone propagates the whole module surface through the fixpoint
(`lib/default.nix:474` re-exports via `inherit (self.modules)`), so the vendored body owns the
top-level eval, the submodule `base` (`types.nix:1375` `inherit (lib.modules) evalModules`), AND every
`base.extendModules` re-entry (`types.nix:1452` → file-local `evalModules`). `lib.types` / `type.merge`
hosted by-reference (verbatim). No selection (that is E3).

**Tech Stack:** Nix, the gen `mkCi` test convention (`cd ci && nix flake check` — authoritative;
`nix-unit --flake` under-reports, do NOT use), the hola parity harness (`parity`/`adapter`/`corpus`/`compose`).

**Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-24-hola-engine-e1-design.md`.

**nixpkgs pin:** the corpus's `nixpkgs` input = `root.inputs.nixpkgs` (flake.lock node `nixpkgs_7`) =
rev `567a49d1913ce81ac6e9582e3553dd90a955875f`. **NOT** `l.nodes.nixpkgs` (`64c08a7`, transitive/gen).
All line citations are against `567a49d`.

**Working repo:** `~/Documents/repos/hola` (`github:sini/hola`), on `main`. Each task is one commit.
Per the user's git discipline: stage specific files by name (never `git add -A/.`); no Co-Authored-By
trailer. **Format before each commit** — gen wires treefmt via `mkCi` but does **not** gate
`nix flake check` on it (`treefmt.flakeCheck = false`), so run the devshell formatter (`nix fmt`,
confirming the exact invocation in the gen devshell) to keep the public history clean. The commit
hook may block on incomplete native tasks — if so, complete the task's status update or commit via
the `!git commit` session escape.

---

## File structure (decomposition locked)

| File | New/Edit | Responsibility |
|---|---|---|
| `lib/engine/vendor/modules.nix` | new (vendored) | Verbatim copy of nixpkgs `lib/modules.nix` @ `567a49d`. The owned body. |
| `lib/engine/vendor/COPYING` | new | nixpkgs MIT license (attribution). |
| `lib/engine/vendor/README.md` | new | Provenance + K9 re-vendor rule. |
| `lib/engine/vendor/modules.broken.nix` | new (test fixture) | Minimal labeled wrapper of `modules.nix` that deliberately diverges on the `valueMeta` surface — proves the gate is non-vacuous. |
| `lib/engine/default.nix` | new | `mkEngine` (the `lib.extend` constructor) + `engine` (real record) + `_brokenProbe` (test-only). |
| `lib/adapter.nix` | edit | Wire `engines.engine` from `./engine`. |
| `lib/default.nix` | edit | Expose the `engine` concern at the hola top level (so tests reach `mkEngine`/`_brokenProbe`). |
| `lib/compose.nix` | edit | Add `engineParity fx` (vanilla vs engine, mirror of `selfParity`). |
| `ci/tests/engine-parity.nix` | new | Gating: `engineParity` over the corpus + non-vacuity probe + vendored-integrity (K9) assertion. |
| `ci/apps.nix` | edit | Add the non-gating `vendor-check` evidence app. |
| `ci/bench/vendor-check.sh` | new | Diffs vendored `modules.nix` against `${NIXPKGS}/lib/modules.nix`. |

---

## Task 0: Vendor the engine body (modules.nix + license + provenance)

**Goal:** Commit a verbatim copy of nixpkgs `lib/modules.nix` @ `567a49d` under `lib/engine/vendor/`,
with its MIT license and a provenance README.

**Files:**
- Create: `lib/engine/vendor/modules.nix`
- Create: `lib/engine/vendor/COPYING`
- Create: `lib/engine/vendor/README.md`

**Acceptance Criteria:**
- [ ] `lib/engine/vendor/modules.nix` is byte-identical to `${nixpkgs}/lib/modules.nix` (the `nixpkgs_7`/`567a49d` input).
- [ ] `COPYING` reproduces nixpkgs' MIT text with the `Copyright (c) 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors` line.
- [ ] `README.md` records the source rev `567a49d` and the K9 rule: "bumping the harness's nixpkgs requires re-vendoring this file and re-running the parity gate."

**Verify:**
```bash
cd ~/Documents/repos/hola/ci
NP=$(nix eval --impure --raw --expr 'toString (builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')
diff -q ../lib/engine/vendor/modules.nix "$NP/lib/modules.nix"   # → no output (identical)
```

**Steps:**

- [ ] **Step 1: Resolve the pinned nixpkgs and copy the files.**
```bash
cd ~/Documents/repos/hola
mkdir -p lib/engine/vendor
NP=$(cd ci && nix eval --impure --raw --expr 'toString (builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')
echo "vendoring from $NP ($(cat "$NP/.git-revision"))"   # expect 567a49d1913ce...
cp "$NP/lib/modules.nix" lib/engine/vendor/modules.nix
cp "$NP/COPYING"         lib/engine/vendor/COPYING
chmod u+w lib/engine/vendor/modules.nix lib/engine/vendor/COPYING   # store files are read-only
```

- [ ] **Step 2: Write `lib/engine/vendor/README.md`.**
```markdown
# Vendored nixpkgs `lib/modules.nix`

`modules.nix` here is a **byte-for-byte copy** of nixpkgs `lib/modules.nix`, vendored so the hola
engine can BE `lib.modules.evalModules` at every recursion level (see the E1 spec, §3 / HC5). It is
**unmodified** at E1; later increments (E3) edit it under the parity gate.

- **Source:** nixpkgs `nixos-unstable`, rev `567a49d1913ce81ac6e9582e3553dd90a955875f`
  (the harness's `nixpkgs` input — flake.lock node `nixpkgs_7`).
- **License:** MIT — see `COPYING` (Copyright (c) 2003-2026 Eelco Dolstra and the Nixpkgs/NixOS contributors).
- **K9 migration rule:** bumping the harness's nixpkgs input requires **re-vendoring** this file
  from the new rev and re-running `cd ci && nix flake check`. `nix run ./ci#vendor-check` reports
  drift against the current input.

`modules.broken.nix` is a **test fixture only** (a deliberately-divergent wrapper proving the
parity gate is non-vacuous) — never imported by the real engine.
```

- [ ] **Step 3: Verify byte-identity and commit.**
```bash
cd ~/Documents/repos/hola
NP=$(cd ci && nix eval --impure --raw --expr 'toString (builtins.getFlake (toString ./.)).inputs.nixpkgs.outPath')
diff -q lib/engine/vendor/modules.nix "$NP/lib/modules.nix" && echo "IDENTICAL"
git add lib/engine/vendor/modules.nix lib/engine/vendor/COPYING lib/engine/vendor/README.md
git commit -m "feat(engine): vendor nixpkgs lib/modules.nix (567a49d) + MIT license"
```

---

## Task 1: Engine constructor + adapter seam

**Goal:** A `{ lib; evalModules }` engine record that owns the vendored body, wired into
`adapter.engines.engine` and reachable as `hola.engine`.

**Files:**
- Create: `lib/engine/default.nix`
- Modify: `lib/adapter.nix` (replace the `# engine = …` placeholder at `:26`)
- Modify: `lib/default.nix` (expose the `engine` concern)
- Test: `ci/tests/engine-parity.nix` (smoke portion; full gate in Task 2)

**Acceptance Criteria:**
- [ ] `hola.adapter.engines.engine` is `{ lib; evalModules }` with both fields present.
- [ ] `adapter.run engines.engine fx` evaluates the synthetic fixture without throwing.
- [ ] Overriding `final.modules` alone is used (no separate `evalModules` override) — documented inline.

**Verify:** `cd ci && nix flake check` → green (smoke test passes).

**Steps:**

- [ ] **Step 1: Write `lib/engine/default.nix`.**
```nix
{ lib }:
let
  # mkEngine: BE lib.modules.evalModules by overriding `final.modules` with a vendored body.
  # Overriding `modules` ALONE suffices — lib/default.nix re-exports the whole module surface via
  # `inherit (self.modules)`, so evalModules/mkIf/mkMerge/mkOverride/filterOverrides/… all resolve
  # to the vendored copy through the fixpoint. `final.types` is re-fixpointed against `final`, so
  # submoduleWith reaches the vendored evalModules at `base`; the vendored file-local extendModules
  # keeps every submodule re-entry inside the owned body (E1 spec §3 / HC5).
  mkEngine =
    modulesFile:
    let
      holaLib = lib.extend (final: _prev: {
        modules = import modulesFile { lib = final; };
      });
    in
    {
      lib = holaLib;
      evalModules = holaLib.evalModules;
    };
in
{
  inherit mkEngine;
  engine = mkEngine ./vendor/modules.nix;
}
```

- [ ] **Step 2: Wire `lib/adapter.nix`.** Replace the placeholder comment (`adapter.nix:26`) inside
  the `engines` set. Add at the top of the `let` (named to avoid shadowing the `engine` attr):
```nix
  engineConcern = import ./engine { inherit lib; };
```
  and in `engines`:
```nix
    engine = engineConcern.engine;
```

- [ ] **Step 3: Expose the engine concern in `lib/default.nix`.** Add `engine = import ./engine args;`
  to the `let` and to the returned attrset (so `hola.engine.mkEngine` is reachable by tests).

- [ ] **Step 4: Add the smoke test to `ci/tests/engine-parity.nix`** (the file is fully fleshed in
  Task 2; start it here). **gen `assertTests` requires two nesting levels** —
  `flake.tests.<suite>.<test> = { expr; expected; }`. A single-test suite must therefore use an inner
  name (`.check`); only `mapAttrs`-built suites (Task 2's `engine-parity`) already have the second level.
```nix
{ hola, ... }:
let
  inherit (hola) adapter corpus;
in
{
  flake.tests.engine-smoke.check = {
    expr =
      let r = adapter.run adapter.engines.engine (corpus.synthetic.mk { });
      in builtins.isAttrs r.config && (adapter.engines.engine ? lib) && (adapter.engines.engine ? evalModules);
    expected = true;
  };
}
```

- [ ] **Step 5: Verify and commit.**
```bash
cd ~/Documents/repos/hola
# format if the repo defines one (treefmt/nix fmt); then:
( cd ci && nix flake check ) 2>&1 | tail -5    # green
git add lib/engine/default.nix lib/adapter.nix lib/default.nix ci/tests/engine-parity.nix
git commit -m "feat(engine): mkEngine lib.extend constructor + adapter.engines.engine seam"
```

---

## Task 2: `engineParity` + the byte-identical corpus gate (the load-bearing proof)

**Goal:** Prove `vanilla == engine` byte-identical across the full corpus, including the real-host
`toplevel.drvPath` tier.

**Files:**
- Modify: `lib/compose.nix` (add `engineParity`)
- Modify: `ci/tests/engine-parity.nix` (add the corpus gate)

**Acceptance Criteria:**
- [ ] `compose.engineParity fx` dispatches on `fx.gate` exactly like `selfParity` (value→`valueEq`,
      drvPath→`drvEq`, throws→both `expectThrowFx`), comparing `engines.vanilla` vs `engines.engine`.
- [ ] `engineParity` is `true` for every corpus fixture: `synthetic`, `priorityFold`, `order`,
      `valueMeta` (reverse-`listOf` quirk), `latticeThrows`, `realHost` (drvPath, `n = 3`).

**Verify:** `cd ci && nix flake check` → all `engine-parity.*` tests pass (green).

**Steps:**

- [ ] **Step 1: Add `engineParity` to `lib/compose.nix`** (mirror `selfParity`, swap `identity`→`engine`):
```nix
  engineParity =
    fx:
    if (fx.gate or "value") == "throws" then
      (expectThrowFx engines.vanilla fx) && (expectThrowFx engines.engine fx)
    else if (fx.gate or "value") == "drvPath" then
      drvEq engines.vanilla engines.engine fx
    else
      valueEq engines.vanilla engines.engine fx;
```
  and add `engineParity` to the returned `inherit` list.

- [ ] **Step 2: Flesh out `ci/tests/engine-parity.nix`** (mirror `self-parity.nix`):
```nix
{ hola, nixpkgs, ... }:
let
  inherit (hola) corpus compose adapter;
  parityFixtures = {
    synthetic     = corpus.synthetic.mk { };
    priorityFold  = corpus.priorityFold.mk { };
    order         = corpus.order.mk { };
    valueMeta     = corpus.valueMeta.mk { };
    latticeThrows = corpus.latticeThrows.mk { };
    realHost      = corpus.realHost.mk { inherit nixpkgs; n = 3; };
  };
in
{
  flake.tests.engine-smoke.check = {
    expr =
      let r = adapter.run adapter.engines.engine (corpus.synthetic.mk { });
      in builtins.isAttrs r.config && (adapter.engines.engine ? lib) && (adapter.engines.engine ? evalModules);
    expected = true;
  };
  flake.tests.engine-parity = builtins.mapAttrs (_: fx: {
    expr = compose.engineParity fx;
    expected = true;
  }) parityFixtures;
}
```

- [ ] **Step 3: Verify and commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake check ) 2>&1 | tail -8     # engine-parity.* all PASS
git add lib/compose.nix ci/tests/engine-parity.nix
git commit -m "feat(compose): engineParity gate — vanilla==engine byte-identical on the corpus"
```

> **Reviewer note:** this is the load-bearing proof. Because the body is verbatim, identity is
> near-tautological *by design* (single-variable isolation of the ownership seam). The gate is shown
> non-vacuous in Task 3.

---

## Task 3: Non-vacuity probe (prove the gate bites)

**Goal:** Demonstrate `engineParity`/`valueEq` returns `false` for a *wrong* engine, so a passing gate
is meaningful. (Every merge internal is file-local in the vendored body, so a faithful perturbation
must edit a vendored variant — this is the vendor-and-own thesis in miniature.)

**Files:**
- Create: `lib/engine/vendor/modules.broken.nix`
- Modify: `lib/engine/default.nix` (export `_brokenProbe`)
- Modify: `ci/tests/engine-parity.nix` (add the probe assertion)

**Acceptance Criteria:**
- [ ] `modules.broken.nix` is a minimal, clearly-labeled wrapper of `./modules.nix` that diverges on
      the `valueMeta` surface (`config.thing`) only.
- [ ] `compose.valueEq engines.vanilla hola.engine._brokenProbe (corpus.valueMeta.mk {})` is `false`.

**Verify:** `cd ci && nix flake check` → `engine-parity.non-vacuity` passes (expected `false` met).

**Steps:**

- [ ] **Step 1: Write `lib/engine/vendor/modules.broken.nix`** (test fixture; NOT the real engine):
```nix
# TEST FIXTURE ONLY — proves the parity gate is non-vacuous (E1 spec §6).
# A correct engine reproduces the same-priority listOf reverse-order quirk ([1],[2] -> [2 1]);
# this wrapper deliberately re-reverses `config.thing`, so engineParity over `valueMeta` flips false.
# Never imported by the real engine (lib/engine/default.nix uses ./modules.nix).
{ lib }:
let
  real = import ./modules.nix { inherit lib; };
in
real
// {
  evalModules =
    args:
    let
      r = real.evalModules args;
    in
    r // { config = r.config // { thing = lib.reverseList (r.config.thing or [ ]); }; };
}
```

- [ ] **Step 2: Export `_brokenProbe` from `lib/engine/default.nix`** (add to the returned set):
```nix
  # Test-only: a deliberately-divergent engine for the non-vacuity probe. NOT in adapter.engines.
  _brokenProbe = mkEngine ./vendor/modules.broken.nix;
```

- [ ] **Step 3: Add the probe to `ci/tests/engine-parity.nix`:**
```nix
  flake.tests.non-vacuity.check = {
    expr = compose.valueEq adapter.engines.vanilla hola.engine._brokenProbe (corpus.valueMeta.mk { });
    expected = false;
  };
```

- [ ] **Step 4: Verify and commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake check ) 2>&1 | tail -8     # non-vacuity passes (gate bites)
git add lib/engine/vendor/modules.broken.nix lib/engine/default.nix ci/tests/engine-parity.nix
git commit -m "test(engine): non-vacuity probe — parity gate flips false on a wrong engine"
```

---

## Task 4: `vendor-check` evidence app + K9 vendored-integrity gate

**Goal:** Mechanically enforce/observe that the vendored body matches the harness's nixpkgs input
(the K9 discipline), without gating CI on an external moving target for the human-facing diff.

**Files:**
- Create: `ci/bench/vendor-check.sh`
- Modify: `ci/apps.nix` (register the app)
- Modify: `ci/tests/engine-parity.nix` (add the gating integrity assertion)

**Acceptance Criteria:**
- [ ] `nix run ./ci#vendor-check` prints a clear "identical" / diff result against `${NIXPKGS}/lib/modules.nix`.
- [ ] A gating test `engine-parity.vendor-integrity` asserts
      `readFile vendor/modules.nix == readFile (nixpkgs + "/lib/modules.nix")` is `true` (verbatim at E1).

**Verify:**
```bash
cd ~/Documents/repos/hola
nix run ./ci#vendor-check                 # → "vendored modules.nix is byte-identical …"
( cd ci && nix flake check ) 2>&1 | tail -5   # vendor-integrity green
```

**Steps:**

- [ ] **Step 1: Write `ci/bench/vendor-check.sh`** (`HOLA_SRC` + `NIXPKGS` are exported by `mkBench`):
```bash
#!/usr/bin/env bash
set -euo pipefail
vendored="$HOLA_SRC/lib/engine/vendor/modules.nix"
upstream="$NIXPKGS/lib/modules.nix"
echo "vendored: $vendored"
echo "upstream: $upstream  (rev $(cat "$NIXPKGS/.git-revision" 2>/dev/null || echo '?'))"
if diff -u "$upstream" "$vendored" > /tmp/vendor-check.diff; then
  echo "OK: vendored modules.nix is byte-identical to the harness nixpkgs input."
else
  echo "DRIFT: vendored modules.nix diverges from the harness nixpkgs input:"
  cat /tmp/vendor-check.diff
  echo "(expected once E3 edits the body; at E1 this must be empty — re-vendor on a nixpkgs bump.)"
fi
```

- [ ] **Step 2: Register the app in `ci/apps.nix`** (in the returned `apps` set):
```nix
      apps.vendor-check = mkBench "vendor-check" [ ] ./bench/vendor-check.sh;
```

- [ ] **Step 3: Add the gating integrity assertion to `ci/tests/engine-parity.nix`:**
```nix
  flake.tests.vendor-integrity.check = {
    # K9: at E1 the vendored body is verbatim. (`nixpkgs` is the resolved input outPath.)
    expr = builtins.readFile ../../lib/engine/vendor/modules.nix
      == builtins.readFile (nixpkgs + "/lib/modules.nix");
    expected = true;
  };
```

- [ ] **Step 4: Verify and commit.**
```bash
cd ~/Documents/repos/hola
nix run ./ci#vendor-check
( cd ci && nix flake check ) 2>&1 | tail -5
git add ci/bench/vendor-check.sh ci/apps.nix ci/tests/engine-parity.nix
git commit -m "feat(ci): vendor-check evidence app + K9 vendored-integrity gate"
```

---

## Done criteria (E1 complete)

- `cd ci && nix flake check` green, including `engine-parity.*` (corpus byte-identity incl. real-host
  drvPath), `non-vacuity` (gate bites), `vendor-integrity` (K9 verbatim).
- `nix run ./ci#vendor-check` reports byte-identical.
- The engine owns every recursion level (top-level + submodule `base` + `base.extendModules`
  re-entries) — the HC5 ownership the `identity` engine cannot reach.
- Push `main` only when the user asks; this is `github:sini/hola` (public) — keep commit messages free
  of any sensitive specifics (none here).

**Then:** E2 (Den-as-corpus on this same body) and E3 (external lazy selection + gen-rebuild
incremental override swapped *inside* the owned body, each parity-gated against this E1 baseline).
