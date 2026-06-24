# hola Parity Harness — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Task tracking:** native CC `TaskCreate` is **NOT** used (the `pre-commit-check-tasks` hook blocks commits while native tasks are open). Track via the checkboxes below + the co-located `.tasks.json`.

**Goal:** Build the hola parity harness (Phase 4, increment 1) — a self-validating, byte-identical contract against `lib.evalModules` that the future hola engine must satisfy — as a new gen-canonical repo `~/Documents/repos/hola`.

**Architecture:** Two tiers, one repo. Tier 1 = contract-as-lib (`parity.nix` oracle + `adapter.nix` seam + parameterized corpus + nix-unit tests, CI-gated). Tier 2 = evidence-as-flake-apps (stat-capture/scaling-curve/floor-decomp/parity-report via the gen ci devshell). Self-validates today (vanilla vs `lib.extend`-passthrough identity); the engine arm slots into `adapter.nix` later.

**Tech Stack:** Nix (pure `lib`), flake-parts, `gen.lib.mkCi` + nix-unit (`flake.tests.<suite>.<test> = { expr; expected; }`), `writeShellApplication`, `NIX_SHOW_STATS`.

**Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-23-parity-harness-design.md` (commit `88af82b`). Section refs (§N) point there.

**Conventions (from `project_hola` / feedback memories):**
- Specs/plans live in `~/Documents/papers/hola-architecture/`; never `docs/superpowers/`.
- Commits: no `Co-Authored-By`, no bylines; stage specific files (never `git add -A`); format before committing (`cd ci && nix fmt`).
- nixpkgs is **injected** (never hardcode the `2f4f625e` path/rev); pin + record it where measured (D7).
- One concern per file; complete code below, not "add X".

---

## File structure

**`~/Documents/repos/gen`** (shipped hub — one prerequisite edit):
- Modify: `ci/mkCi.nix` — add `extraModules ? [ ]` seam.
- Create: `ci/tests/extramodules.nix` — regression test for the seam.

**`~/Documents/repos/hola`** (new repo):
```
flake.nix              root: lib = import ./. { lib = nixpkgs.lib; }; __functor
default.nix            { pkgs ? import <nixpkgs> {}, lib ? pkgs.lib }: import ./lib { inherit lib; }
lib/
  default.nix          explicit imports + compose layer (cross-concern wiring)
  parity.nix           force · diff · diffAt · locate · drvPathGate · expectThrow · withOptionShape
  adapter.nix          engines.{vanilla,identity} · run
  compose.nix          test-facing helpers: selfParity · expectThrowFx · valueEq · drvEq
  corpus/
    default.nix        registry { <name> = { mk; defaultParams; gate; tier }; }
    synthetic.nix      { lib, n, ndecls, layers } -> fixture   (from dual.nix)
    landmines.nix      hc3_* ports, each with `expected`
    real-host.nix      { lib, nixpkgs, n } -> NixOS fixture     (from checktest.nix)
    floor.nix          justImport · libOnly · modScale          (perf-only)
ci/
  flake.nix            gen.lib.mkCi { ... extraModules = [ ./apps.nix ]; }
  apps.nix             flake-parts module: perSystem.apps.{stat-capture,scaling-curve,floor-decomp,parity-report}
  bench/               writeShellApplication payloads + the NIX_SHOW_STATS extractor
  tests/
    smoke.nix
    oracle.nix         unit-tests diff/locate/drvPathGate/expectThrow  (oracle SOUNDNESS proof)
    self-parity.nix    vanilla vs identity over the parity corpus     (seam transparency proof)
    landmines.nix      hc3_* known resolved values / expected throws
README.md · LICENSE · .envrc · .github/{workflows/ci.yml,FUNDING.yml} · .gitignore   (from gen-rebuild)
```

---

### Task 0: `gen.lib.mkCi` — add `extraModules` seam (prerequisite)

**Goal:** Let `mkCi` consumers inject extra flake-parts modules (hola needs `perSystem.apps`); verified absent today (§14). Backward-compatible (defaults to `[ ]`).

**Files:**
- Modify: `~/Documents/repos/gen/ci/mkCi.nix` (signature line 17–22; imports line 38–45)
- Create: `~/Documents/repos/gen/ci/tests/extramodules.nix`

**Acceptance Criteria:**
- [ ] `mkCi` accepts `extraModules ? [ ]`; modules in it are imported into `mkFlake`.
- [ ] Existing consumers unaffected (gen + gen-rebuild flake checks still green).
- [ ] A test proves an `extraModules`-supplied `perSystem.apps.<x>` surfaces on the result flake.

**Verify:** `cd ~/Documents/repos/gen && nix flake check` → green; `cd ~/Documents/repos/gen-rebuild/ci && nix flake check --override-input gen ~/Documents/repos/gen` → green.

**Steps:**

- [ ] **Step 1: Write the failing regression test.** `ci/tests/extramodules.nix` — assert the inner `mkCi` lambda exposes the `extraModules` arg (a clean RED→GREEN on the signature). The load-bearing *integration* proof is the gen-rebuild `--override-input` flake-check in **Verify**.

```nix
{ inputs, ... }:
let
  mkCi = import ../mkCi.nix { inherit inputs; };
in
{
  flake.tests.extramodules.has-seam = {
    expr = (builtins.functionArgs mkCi) ? extraModules;
    expected = true;
  };
}
```

Run: `cd ~/Documents/repos/gen/ci && nix-unit --flake .#tests.extramodules` → FAILS (no `extraModules` arg yet). (No `_empty` dir needed — `functionArgs` does not force `mkCi`'s body.)

- [ ] **Step 2: Implement the seam.** Edit `ci/mkCi.nix`:

```nix
{
  inputs,
  name,
  testModules,
  specialArgs ? { },
  extraModules ? [ ],
}:
# ... unchanged let ...
(resolve "flake-parts").lib.mkFlake
  { inherit inputs; specialArgs = { inherit name genInputs; } // specialArgs; }
  {
    imports = [
      (resolve "treefmt-nix").flakeModule
      (resolve "devshell").flakeModule
      (resolve "flake-root").flakeModule
      (resolve "git-hooks-nix").flakeModule
      ./flakeModule.nix
      (import-tree testModules)
    ] ++ extraModules;
  }
```

- [ ] **Step 3: Verify + commit + push.** Composition-safety per §14: `flakeModule.nix` sets no `perSystem.apps`, flake-parts' core `apps` is free → additive.

Run: `cd ~/Documents/repos/gen && nix flake check` and `cd ~/Documents/repos/gen-rebuild/ci && nix flake check --override-input gen ~/Documents/repos/gen` → both green.

```bash
cd ~/Documents/repos/gen && nix fmt
git add ci/mkCi.nix ci/tests/extramodules.nix
git commit -m "feat(mkCi): add extraModules seam for consumer flake-parts modules"
git push
```

> hola's `ci/flake.nix` consumes `github:sini/gen`, so this must be **pushed** before hola CI is green. During local dev, hola CI can `--override-input gen ~/Documents/repos/gen`.

---

### Task 1: Scaffold the hola repo (green skeleton, smoke test)

**Goal:** A gen-canonical leaf repo whose `cd ci && nix flake check` passes a smoke test. No oracle yet.

**Files (create):** `flake.nix`, `default.nix`, `lib/default.nix` (stub), `lib/parity.nix` (stub `{}`), `lib/adapter.nix` (stub `{}`), `ci/flake.nix`, `ci/tests/smoke.nix`, `.envrc`, `.gitignore`, `LICENSE`, `README.md` (skeleton), `.github/workflows/ci.yml`, `.github/FUNDING.yml`.

**Acceptance Criteria:**
- [ ] `git init`'d repo with the leaf skeleton.
- [ ] `cd ci && nix flake check` green (smoke `test-true`).
- [ ] No apps yet (added Task 8); plain `gen.lib.mkCi` for now.

**Verify:** `cd ~/Documents/repos/hola/ci && nix flake check --override-input gen ~/Documents/repos/gen` → green.

**Steps:**

- [ ] **Step 1: init + clone boilerplate.** `mkdir -p ~/Documents/repos/hola && cd ~/Documents/repos/hola && git init`. Copy verbatim from gen-rebuild (then `git add` by name): `.envrc` (`use flake ./ci`), `.gitignore`, `LICENSE`, `.github/workflows/ci.yml`, `.github/FUNDING.yml`.

- [ ] **Step 2: root `flake.nix`** (leaf — nixpkgs only):

```nix
{
  description = "hola: parity harness for a pure-gen module engine hosting unmodified nixpkgs modules";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs =
    { nixpkgs, ... }:
    {
      lib = import ./. { lib = nixpkgs.lib; };
      __functor = _: import ./.;
    };
}
```

- [ ] **Step 3: `default.nix`** (leaf, mirrors gen-aspects):

```nix
{
  pkgs ? import <nixpkgs> { },
  lib ? pkgs.lib,
}:
import ./lib { inherit lib; }
```

- [ ] **Step 4: `lib/default.nix`** (explicit imports + compose; deviates from gen-rebuild's blind `//`-fold because hola wires concerns together — justified):

```nix
{ lib }:
let
  args = { inherit lib; };
  parity = import ./parity.nix args;
  adapter = import ./adapter.nix args;
  corpus = import ./corpus args;            # corpus/default.nix; added Task 5-6 (stub {} now)
  compose = import ./compose.nix (args // { inherit parity adapter corpus; }); # added Task 7
in
{
  inherit parity adapter corpus;
}
// compose
```

> For Task 1 only, stub `lib/corpus` → create `lib/corpus/default.nix = { lib }: { }`, `lib/compose.nix = { lib, parity, adapter, corpus }: { }`, `lib/parity.nix = { lib }: { }`, `lib/adapter.nix = { lib }: { }`. They fill in later tasks.

- [ ] **Step 5: `ci/flake.nix`** (leaf — gen + nixpkgs only; NO extraModules yet):

```nix
{
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };
  outputs =
    inputs@{ gen, nixpkgs, ... }:
    let
      hola = import ../. { lib = nixpkgs.lib; };
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "hola";
      testModules = ./tests;
      # nixpkgs threaded for the real-host fixture (eval-config import); no re-edit later.
      specialArgs = {
        inherit hola;
        nixpkgs = nixpkgs.outPath or nixpkgs;
      };
    };
}
```

- [ ] **Step 6: `ci/tests/smoke.nix`** (clone gen-rebuild):

```nix
{ ... }:
{ flake.tests.smoke.test-true = { expr = true; expected = true; }; }
```

- [ ] **Step 7: README skeleton** to the gen-canonical section order (title+badges, TOC, Overview, Terminology, Gen Ecosystem table, Quick Start, API Reference [TBD], Testing, Theoretical Foundations, License). API Reference filled in Task 9.

- [ ] **Step 8: verify + commit.**

Run: `cd ~/Documents/repos/hola/ci && nix flake check --override-input gen ~/Documents/repos/gen` → green; `cd ~/Documents/repos/hola && nix fmt`.

```bash
cd ~/Documents/repos/hola
git add flake.nix default.nix lib ci .envrc .gitignore LICENSE README.md .github
git commit -m "feat: scaffold hola repo (gen-canonical leaf, smoke test green)"
```

---

### Task 2: `parity.nix` — `force` + `diffAt` + `diff` + `locate`

**Goal:** The structural, order-sensitive, throw-robust diff oracle (§6) + its soundness unit tests. This is the heart of the contract.

**Files:** Modify `lib/parity.nix`; Create `ci/tests/oracle.nix`.

**Acceptance Criteria:**
- [ ] `diff` recurses attrsets over the key union with `"__absent"` sentinel; lists length-first then order-sensitive by index; scalars `==`; `identical = divergences == []`.
- [ ] `diff` `tryEval`s each arm — one-arm-throw → root divergence, never an abort.
- [ ] `path` = list of keys/indices from the projection root.

**Verify:** `cd ci && nix-unit --flake .#tests.oracle` → all PASS.

**Steps:**

- [ ] **Step 1: Write `ci/tests/oracle.nix`** (RED):

```nix
{ hola, ... }:
let p = hola.parity;
in {
  flake.tests.oracle = {
    equal           = { expr = (p.diff { a = { x = 1; }; b = { x = 1; }; }).identical;      expected = true; };
    differ-scalar   = { expr = (p.diff { a = { x = 1; }; b = { x = 2; }; }).divergences;     expected = [ { path = [ "x" ]; aValue = 1; bValue = 2; } ]; };
    missing-key     = { expr = (p.diff { a = { x = 1; }; b = { }; }).divergences;            expected = [ { path = [ "x" ]; aValue = 1; bValue = "__absent"; } ]; };
    list-order      = { expr = (p.diff { a = [ "a" "b" ]; b = [ "b" "a" ]; }).identical;     expected = false; };
    list-length     = { expr = (p.diff { a = [ "a" ]; b = [ "a" "b" ]; }).divergences;       expected = [ { path = [ "length" ]; aValue = 1; bValue = 2; } ]; };
    nested          = { expr = (p.diff { a = { s = { y = [ 1 ]; }; }; b = { s = { y = [ 2 ]; }; }; }).divergences; expected = [ { path = [ "s" "y" 0 ]; aValue = 1; bValue = 2; } ]; };
    one-arm-throw   = { expr = (p.diff { a = { x = 1; }; b = (throw "boom"); }).identical;    expected = false; };
    locate-head     = { expr = (p.locate { a = { x = 1; }; b = { x = 2; }; }).path;          expected = [ "x" ]; };
  };
}
```

Run: `cd ci && nix-unit --flake .#tests.oracle` → FAILS.

- [ ] **Step 2: Implement in `lib/parity.nix`:**

```nix
{ lib }:
let
  inherit (builtins) isAttrs isList attrNames tryEval deepSeq length elemAt head;

  force = x: deepSeq x x;

  diffAt =
    path: a: b:
    if isAttrs a && isAttrs b then
      let keys = lib.unique (attrNames a ++ attrNames b);
      in lib.concatMap (
        k:
        if (a ? ${k}) && (b ? ${k}) then
          diffAt (path ++ [ k ]) a.${k} b.${k}
        else
          [ {
            path = path ++ [ k ];
            aValue = if a ? ${k} then a.${k} else "__absent";
            bValue = if b ? ${k} then b.${k} else "__absent";
          } ]
      ) keys
    else if isList a && isList b then
      if length a != length b then
        [ { path = path ++ [ "length" ]; aValue = length a; bValue = length b; } ]
      else
        lib.concatMap (i: diffAt (path ++ [ i ]) (elemAt a i) (elemAt b i)) (lib.range 0 (length a - 1))
    else if a == b then [ ]
    else [ { inherit path; aValue = a; bValue = b; } ];

  diff =
    { a, b }:
    let
      ea = tryEval (force a);
      eb = tryEval (force b);
    in
    if ea.success && eb.success then
      let divs = diffAt [ ] ea.value eb.value;
      in { identical = divs == [ ]; divergences = divs; }
    else
      {
        identical = false;
        divergences = [ {
          path = [ ];
          aValue = if ea.success then ea.value else "<<throw>>";
          bValue = if eb.success then eb.value else "<<throw>>";
        } ];
      };

  locate = { a, b }: let d = diff { inherit a b; }; in if d.identical then null else head d.divergences;
in
{ inherit force diffAt diff locate; }
```

- [ ] **Step 3: verify + commit.** `cd ci && nix-unit --flake .#tests.oracle` → PASS; `nix fmt`.

```bash
git add lib/parity.nix ci/tests/oracle.nix
git commit -m "feat(parity): structural order-sensitive diff oracle + soundness tests"
```

---

### Task 3: `parity.nix` — `drvPathGate` + `expectThrow` + `withOptionShape`

**Goal:** The remaining oracle pieces (§6): the host-tier gate, the throws primitive, and the option-shape pick-builder.

**Files:** Modify `lib/parity.nix`; extend `ci/tests/oracle.nix`.

**Acceptance Criteria:**
- [ ] `drvPathGate` `tryEval`s `config.system.build.toplevel.drvPath` per arm; throw → divergence (never abort).
- [ ] `expectThrow projection` returns **did-throw** (`!success`).
- [ ] `withOptionShape` augments a `pick` with the option-name set + per-path `getSubOptions` names.

**Verify:** `cd ci && nix-unit --flake .#tests.oracle` → all PASS.

**Steps:**

- [ ] **Step 1: extend `oracle.nix`** (RED). `drvPathGate` (mock `{ config.system.build.toplevel.drvPath = "/nix/store/aaa"; }` equal/unequal); `expectThrow` (`expr = p.expectThrow (throw "x"); expected = true;` and `expr = p.expectThrow 1; expected = false;`); and `withOptionShape` against a real eval result (uses `inputs.nixpkgs.lib` directly — no adapter dep, keeps blockedBy [2]):

```nix
{ hola, inputs, ... }:
let
  lib = inputs.nixpkgs.lib;
  p = hola.parity;
  result = lib.evalModules {
    modules = [ { options.svc = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule { options.port = lib.mkOption { type = lib.types.int; default = 0; }; });
      default = { };
    }; } ];
  };
  picked = p.withOptionShape { subOptionPaths = { svc = [ "svc" "*" ]; }; } result;
in
{
  flake.tests.oracle.withOptionShape-subopts = { expr = picked.__subOptions.svc; expected = [ "port" ]; };
  flake.tests.oracle.withOptionShape-names = { expr = builtins.elem "svc" picked.__optionNames; expected = true; };
}
```

- [ ] **Step 2: implement** (append to `parity.nix`'s `let`, extend the result set):

```nix
  drvPathGate =
    { a, b }:
    let
      ea = tryEval a.config.system.build.toplevel.drvPath;
      eb = tryEval b.config.system.build.toplevel.drvPath;
    in
    if ea.success && eb.success then
      { identical = ea.value == eb.value; aDrv = ea.value; bDrv = eb.value; }
    else
      {
        identical = false;
        aDrv = if ea.success then ea.value else "<<throw>>";
        bDrv = if eb.success then eb.value else "<<throw>>";
      };

  # `projection` = an already-picked value thunk; the engine:fx wrapper is in compose.nix (§6).
  expectThrow = projection: !(tryEval (force projection)).success;

  # pick-builder: augments a base pick (result -> attrset) with option-shape data.
  # subOptionPaths :: { <optionName> = <loc list>; }, e.g. { svc = [ "svc" "*" ]; }
  # NOTE: getSubOptions (and result.options) always carry the synthetic `_module`
  # pseudo-option — filter it so the surface is the real option names only.
  withOptionShape =
    { basePick ? (_: { }), options ? null, subOptionPaths ? { } }:
    result:
    let
      dropModule = builtins.filter (n: n != "_module");
    in
    (basePick result)
    // {
      __optionNames = if options != null then options else dropModule (attrNames result.options);
      __subOptions = lib.mapAttrs (
        opt: loc: dropModule (attrNames (result.options.${opt}.type.getSubOptions loc))
      ) subOptionPaths;
    };
```

Add `drvPathGate expectThrow withOptionShape` to the `inherit` in the result.

- [ ] **Step 3: verify + commit.** `nix-unit --flake .#tests.oracle` → PASS; `nix fmt`.

```bash
git add lib/parity.nix ci/tests/oracle.nix
git commit -m "feat(parity): drvPathGate + expectThrow + withOptionShape"
```

---

### Task 4: `adapter.nix` — `engines` + `run`

**Goal:** The engine seam (§7): `vanilla`, the `lib.extend`-passthrough `identity`, and `run` that applies the fixture-schema `?` defaults (a bare `inherit` would throw).

**Files:** Modify `lib/adapter.nix`; Create `ci/tests/adapter.nix`.

**Acceptance Criteria:**
- [ ] Engines are records `{ lib; evalModules }`; `run` calls `engine.evalModules`, applies `specialArgs ? {}`, omits `class` when null.
- [ ] `identity.lib` is the `lib.extend` override; `run identity` byte-identical to `run vanilla`.
- [ ] `runHost` threads `engine.lib` into eval-config (the host-tier seam).

**Verify:** `cd ci && nix-unit --flake .#tests.adapter` → PASS.

**Steps:**

- [ ] **Step 1: `ci/tests/adapter.nix`** (RED): a trivial fixture `{ modules = [ ({ lib, ... }: { options.x = lib.mkOption { default = 1; }; }) ]; }` with `specialArgs`/`class` omitted; assert `(run vanilla fx).config.x == 1` (proves `run` doesn't throw on omitted optionals) and `(run vanilla fx).config == (run identity fx).config`.

- [ ] **Step 2: implement `lib/adapter.nix`:**

```nix
{ lib }:
let
  engines = {
    # Each engine carries its lib AND evalModules so the host tier (runHost) can thread the
    # engine's possibly-extended lib into eval-config.
    vanilla = { lib = lib; evalModules = lib.evalModules; };
    # identity: lib.extend passthrough — byte-identical output, routes through the SAME override
    # seam the engine arm will later replace (submodule extendModules bypass, §4 HC5).
    identity =
      let
        elib = lib.extend (
          final: prev: { modules = prev.modules // { evalModules = a: prev.modules.evalModules a; }; }
        );
      in
      { lib = elib; evalModules = elib.evalModules; };
    # engine = { lib = holaLib; evalModules = holaLib.evalModules; };  # added in the engine increment
  };

  # value / synthetic / landmine tier:
  run =
    engine: fx:
    engine.evalModules (
      { inherit (fx) modules; specialArgs = fx.specialArgs or { }; }
      // (if (fx.class or null) == null then { } else { inherit (fx) class; })
    );

  # host tier (gate="drvPath"): dual-run through eval-config, threading the engine's lib so the
  # override reaches the host evaluator (eval-config builds its evaluator from its `lib` arg).
  runHost =
    engine: fx:
    import fx.evalConfig {
      inherit (engine) lib;
      system = "x86_64-linux";
      modules = fx.modules;
    };
in
{ inherit engines run runHost; }
```

- [ ] **Step 3: verify + commit.**

```bash
git add lib/adapter.nix ci/tests/adapter.nix
git commit -m "feat(adapter): vanilla/identity engines + default-applying run"
```

---

### Task 5: corpus — `synthetic` + `landmines`

**Goal:** Port the package-free synthetic scaling fixture (`dual.nix`) and the hc3_* merge landmines, each with a known `expected`. Build the corpus registry. (§8)

**Files:** Create `lib/corpus/{default.nix,synthetic.nix,landmines.nix}`; Create `ci/tests/landmines.nix`.

**Acceptance Criteria:**
- [ ] `synthetic.mk { n; ndecls; layers }` → fixture (attrsOf submodule, mkMerge priority layers), `gate="value"`.
- [ ] landmines: `priorityFold` → `["c"]`; `order` (mkBefore/mkAfter/mkOrder, from `hc3_l1`); `latticeThrows` (`gate="throws"`); `valueMeta`.
- [ ] Registry `corpus = { <name> = { mk; defaultParams; gate; tier }; }`; nixpkgs is **not** baked in (only `lib`; real-host's nixpkgs comes at `mk` time, Task 6).

**Verify:** `cd ci && nix-unit --flake .#tests.landmines` → PASS (resolved values match).

**Steps:**

- [ ] **Step 1: `ci/tests/landmines.nix`** (RED) — value landmines assert `pick (run vanilla (mk {})) == expected`; throws landmines assert `parity.expectThrow (pick (run vanilla (mk {}))) == true`. Uses only parity + adapter (Task 3/4 symbols), NOT compose:

```nix
{ hola, ... }:
let
  inherit (hola) parity corpus;
  inherit (hola.adapter) run engines;
  pf = corpus.priorityFold.mk { };
  lt = corpus.latticeThrows.mk { };
in
{
  flake.tests.landmines.priorityFold = { expr = pf.pick (run engines.vanilla pf); expected = pf.expected; };
  flake.tests.landmines.latticeThrows = { expr = parity.expectThrow (lt.pick (run engines.vanilla lt)); expected = true; };
}
```

- [ ] **Step 2: implement `lib/corpus/synthetic.nix`** (parameterized port of `dual.nix`, nixpkgs-free; each element is an `mkMerge` of `layers` priority defs so the fold runs even at defaults — default `layers=2`):

```nix
{ lib }:
{
  mk =
    { n ? 50, ndecls ? 20, layers ? 2 }:
    let
      optNames = map (i: "o${toString i}") (lib.range 1 ndecls);
      sub = lib.types.submodule { options = lib.genAttrs optNames (_: lib.mkOption { type = lib.types.str; default = ""; }); };
      # o1 is an mkMerge of `layers` priority contributions (exercises filterOverrides / the fold).
      elemVal = lib.mkMerge (map (l: { o1 = lib.mkOverride (100 - l) "v${toString l}"; }) (lib.range 1 layers));
    in
    {
      gate = "value";
      pick = e: e.config.things;
      modules = [
        { options.things = lib.mkOption { type = lib.types.attrsOf sub; default = { }; }; }
        { config.things = lib.genAttrs (map (e: "e${toString e}") (lib.range 1 n)) (_: elemVal); }
      ];
    };
}
```

> Implementer: mirror `analysis/experiments/cost-decomposition/dual.nix` (knobs n/ndecls/layers; n elements; per-element mkMerge of `layers` priority contributions). The above is the green skeleton.

- [ ] **Step 3: implement `lib/corpus/landmines.nix`** (ports of `hc3_{l1,order,lattice,meta}.nix`, package-free; `pick` takes the eval result). Example (`priorityFold`, from `hc3_l1`):

```nix
{ lib }:
let mkList = defs: { gate = "value"; pick = e: e.config.thing; modules = [ { options.thing = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ ]; }; } ] ++ defs; };
in {
  priorityFold = {
    mk = _: (mkList [
      { config.thing = [ "a" ]; }
      { config.thing = lib.mkForce [ "c" ]; }
      { config.thing = lib.mkDefault [ "d" ]; }
    ]) // { expected = [ "c" ]; };
  };
  order      = { mk = _: /* hc3_l1 mkBefore/mkAfter/mkOrder -> expected ["first" "mid" "last"] */ ...; };
  latticeThrows = { mk = _: { gate = "throws"; pick = e: e.config.n; modules = [ { options.n = lib.mkOption { type = lib.types.int; }; } { config.n = lib.mkForce 1; } { config.n = lib.mkForce 2; } ]; }; };
  valueMeta  = { mk = _: /* hc3_meta valueMeta surface, expected resolved value */ ...; };
}
```

> Implementer: open each `hc3_*.nix` source and copy the exact module defs + the empirically-verified resolved value into `expected` (e.g. `hc3_l1` → `[ "c" ]`, confirmed live in review). `latticeThrows` sets no `expected` (throws gate).

- [ ] **Step 4: `lib/corpus/default.nix`** (registry):

```nix
{ lib }:
let
  synthetic = import ./synthetic.nix { inherit lib; };
  landmines = import ./landmines.nix { inherit lib; };
in
{
  synthetic = { inherit (synthetic) mk; defaultParams = { n = 50; ndecls = 20; layers = 1; }; gate = "value"; tier = "both"; };
}
// lib.mapAttrs (_: lm: { inherit (lm) mk; defaultParams = { }; gate = (lm.mk { }).gate; tier = "parity"; }) landmines;
```

- [ ] **Step 5: verify + commit.**

```bash
git add lib/corpus/synthetic.nix lib/corpus/landmines.nix lib/corpus/default.nix ci/tests/landmines.nix
git commit -m "feat(corpus): synthetic scaling fixture + hc3 merge landmines"
```

---

### Task 6: corpus — `real-host` + `floor`

**Goal:** Port the eval-config-backed real-host fixture (`checktest.nix`, drvPath gate, nixpkgs injected at `mk`-time) and the H1 floor baselines — **lib code only**. The real-host *self-parity test* lands in Task 7 (it needs compose's `runHost`/`drvEq`). (§8)

**Files:** Create `lib/corpus/{real-host.nix,floor.nix}`; extend `lib/corpus/default.nix`. (No test file here; no `ci/flake.nix` edit — `nixpkgs` was threaded in Task 1.)

**Acceptance Criteria:**
- [ ] `realHost.mk { nixpkgs; n }` → fixture with `class="nixos"`, `gate="drvPath"`, an `evalConfig` path, building N systemd.services.
- [ ] `floor.{justImport,libOnly,modScale}` present, `tier="perf"`, no parity gate.
- [ ] nixpkgs path is a **parameter** (no hardcoded `2f4f625e`).

**Verify:** `cd ci && nix flake check --override-input gen ~/Documents/repos/gen` → green (lib evals; fixtures construct; existing suites still pass). The drvPath self-parity assertion is added in Task 7.

> This task is a fixture **port** (config, not logic): no standalone RED test — the fixtures are exercised by Task 7's `self-parity.nix`. Its commit is the lib port; flake-check-green is the gate.

**Steps:**

- [ ] **Step 1: implement `lib/corpus/real-host.nix`** (port of `checktest.nix`; `lib` from the outer arg, `nixpkgs` at `mk`-time; carries `fsType` so eval-config builds):

```nix
{ lib }:
{
  mk =
    { nixpkgs, n ? 5 }:
    {
      class = "nixos";
      gate = "drvPath";
      evalConfig = nixpkgs + "/nixos/lib/eval-config.nix";
      # host modules; dual-run through eval-config via compose.runHost (threads engine.lib, Task 4/7).
      modules = [
        {
          config = {
            networking.hostName = "parity";
            boot.loader.grub.enable = false;
            fileSystems."/" = { device = "x"; fsType = "ext4"; };   # fsType REQUIRED or eval-config throws
            system.stateVersion = "24.05";
          };
        }
        { config.systemd.services = lib.genAttrs (map (i: "svc${toString i}") (lib.range 1 n)) (_: { script = "true"; wantedBy = [ "multi-user.target" ]; }); }
      ];
    };
}
```

> Implementer: mirror `checktest.nix`'s exact host-module set so `config.system.build.toplevel.drvPath` builds.

- [ ] **Step 2: implement `lib/corpus/floor.nix`** (ports of `bench_*.nix`, perf-only, nixpkgs as arg):

```nix
{ lib }:
{
  justImport = { tier = "perf"; expr = { nixpkgs }: builtins.attrNames (import nixpkgs { }); };
  libOnly    = { tier = "perf"; expr = { nixpkgs }: (import (nixpkgs + "/lib")).version; };
  modScale   = { tier = "perf"; expr = { ... }: /* 200-module no-pkgs evalModules, from bench_mod_scale.nix */ ...; };
}
```

- [ ] **Step 3: extend `corpus/default.nix`** to include `realHost` (`tier="both"`, `gate="drvPath"`) and `floor` (a `floor` sub-attr; perf-only, excluded from the parity sweep — see Task 7's `parityCorpus` filter).

- [ ] **Step 4: verify + commit.** `cd ci && nix flake check --override-input gen ~/Documents/repos/gen` → green.

```bash
git add lib/corpus/real-host.nix lib/corpus/floor.nix lib/corpus/default.nix
git commit -m "feat(corpus): eval-config real-host (drvPath gate) + H1 floor baselines"
```

---

### Task 7: `compose.nix` + Tier-1 self-parity gate

**Goal:** Wire run+pick+oracle into test-facing helpers and add `self-parity.nix` — the self-validating contract over the whole parity corpus (value/drvPath/throws). (§10)

**Files:** Modify `lib/compose.nix`; Create `ci/tests/self-parity.nix`. (`lib/default.nix` already wires compose from Task 1.)

**Acceptance Criteria:**
- [ ] `compose` exposes `valueEq e1 e2 fx`, `drvEq` (via `runHost`), `expectThrowFx`, `selfParity fx`.
- [ ] `self-parity.nix` asserts, per parity-corpus fixture (value/drvPath/throws), `selfParity fx == true` — including the real-host drvPath gate.
- [ ] `expectThrowFx engine fx` matches §6's `engine: fx:` signature; picks receive the full eval result.

**Verify:** `cd ci && nix flake check --override-input gen ~/Documents/repos/gen` → ALL suites green (smoke, oracle, adapter, landmines, self-parity).

**Steps:**

- [ ] **Step 1: `ci/tests/self-parity.nix`** (RED) — explicit parity-fixture set (floor/perf excluded by omission), each asserts `selfParity == true`; `realHost` gets `nixpkgs` from specialArgs:

```nix
{ hola, nixpkgs, ... }:
let
  inherit (hola) corpus compose;
  parityFixtures = {
    synthetic = corpus.synthetic.mk { };
    priorityFold = corpus.priorityFold.mk { };
    latticeThrows = corpus.latticeThrows.mk { };
    realHost = corpus.realHost.mk { inherit nixpkgs; n = 3; };
    # order / valueMeta added when those landmine ports land
  };
in
{
  flake.tests.self-parity = builtins.mapAttrs (_: fx: { expr = compose.selfParity fx; expected = true; }) parityFixtures;
}
```

- [ ] **Step 2: implement `lib/compose.nix`** (engine records; `runHost` for the host tier; plain application — no `|>`; defensive `gate or "value"`):

```nix
{ lib, parity, adapter, corpus }:
let
  inherit (adapter) run runHost engines;
  pickOf = fx: fx.pick or (r: r.config);                    # picks receive the full eval RESULT
  valueEq = e1: e2: fx: (parity.diff { a = pickOf fx (run e1 fx); b = pickOf fx (run e2 fx); }).identical;
  drvEq = e1: e2: fx: (parity.drvPathGate { a = runHost e1 fx; b = runHost e2 fx; }).identical;
  expectThrowFx = engine: fx: parity.expectThrow (pickOf fx (run engine fx));   # §6 engine:fx signature
  selfParity =
    fx:
    if (fx.gate or "value") == "throws" then (expectThrowFx engines.vanilla fx) && (expectThrowFx engines.identity fx)
    else if (fx.gate or "value") == "drvPath" then drvEq engines.vanilla engines.identity fx
    else valueEq engines.vanilla engines.identity fx;
in
{ inherit valueEq drvEq expectThrowFx selfParity; }
```

- [ ] **Step 3: verify whole suite + commit.** `cd ci && nix flake check --override-input gen ~/Documents/repos/gen` → green.

```bash
git add lib/compose.nix ci/tests/self-parity.nix
git commit -m "feat(compose): self-parity gate over the parity corpus (incl. real-host drvPath)"
```

---

### Task 8: Tier-2 — `apps.nix` + `bench/` + extraModules wiring

**Goal:** The four evidence apps via `perSystem.apps` (§11), wired through the Task-0 `extraModules` seam. No measured number gates CI.

**Files:** Create `ci/apps.nix`, `ci/bench/{stat-capture.sh,scaling-curve.sh,floor-decomp.sh,parity-report.sh,extract.jq}`; Modify `ci/flake.nix` (add `extraModules = [ ./apps.nix ]`).

**Acceptance Criteria:**
- [ ] `nix run ./ci#stat-capture -- synthetic --params n=50` → one-line JSON with the §3 field set + `nixpkgsRev` + `nixVersion`.
- [ ] `scaling-curve`, `floor-decomp`, `parity-report` runnable; exit 0 (evidence).
- [ ] Fixtures addressed by registry `name`; params via `--params k=v`.

**Verify:** `cd ci && nix flake check --override-input gen ~/Documents/repos/gen` green; `nix run ./ci#stat-capture -- synthetic` emits JSON.

**Steps:**

- [ ] **Step 1: `ci/bench/stat-capture.sh`** — the cortex recipe (`NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=… nix-instantiate --eval --strict`), `extract.jq` pulls the six fields; append `nixpkgsRev`/`nixVersion`. (Adapt zen `run-realistic-bench.sh:21-37`.)

- [ ] **Step 2: `ci/apps.nix`** (flake-parts module; composition-safe per §14):

```nix
{
  perSystem =
    { pkgs, ... }:
    let
      mkBench = name: runtimeInputs: text: {
        type = "app";
        program = "${pkgs.writeShellApplication { inherit name runtimeInputs text; }}/bin/${name}";
      };
      common = [ pkgs.nix pkgs.jq ];
    in
    {
      apps.stat-capture = mkBench "stat-capture" common (builtins.readFile ./bench/stat-capture.sh);
      apps.scaling-curve = mkBench "scaling-curve" common (builtins.readFile ./bench/scaling-curve.sh);
      apps.floor-decomp = mkBench "floor-decomp" common (builtins.readFile ./bench/floor-decomp.sh);
      apps.parity-report = mkBench "parity-report" (common ++ [ pkgs.hyperfine ]) (builtins.readFile ./bench/parity-report.sh);
    };
}
```

- [ ] **Step 3: wire `ci/flake.nix`** — `gen.lib.mkCi { ...; extraModules = [ ./apps.nix ]; }`.

- [ ] **Step 4: verify + commit.**

```bash
git add ci/apps.nix ci/bench ci/flake.nix
git commit -m "feat(ci): Tier-2 evidence apps via gen mkCi extraModules seam"
```

---

### Task 9: README API reference + finalize

**Goal:** Fill the README API Reference + Theoretical Foundations table; record the nixpkgs rev pin; document the engine-arm seam. (§5, §15)

**Files:** Modify `README.md`.

**Acceptance Criteria:**
- [ ] API Reference covers `parity.*`, `adapter.*`, `compose.*`, `corpus`.
- [ ] Records nixpkgs rev + "engine arm slots into `adapter.engines.engine`".
- [ ] `cd ci && nix flake check` green; `nix fmt` clean (mdformat).

**Verify:** `cd ci && nix flake check` green.

**Steps:**

- [ ] **Step 1:** write the API reference + ecosystem table + foundations mapping.
- [ ] **Step 2:** `nix fmt`; verify; commit.

```bash
git add README.md
git commit -m "docs: API reference + theoretical foundations for the parity harness"
```

---

## Done criteria (whole increment)
- [ ] `cd ~/Documents/repos/hola/ci && nix flake check` green (all suites).
- [ ] Self-parity proven (vanilla vs identity) across synthetic + landmines + real-host.
- [ ] Tier-2 apps runnable via `nix run ./ci#…`.
- [ ] gen `extraModules` seam landed + pushed.
- [ ] Engine arm seam ready (`adapter.engines.engine`), engine + engine-parity tests **out of scope** (next increment, after gen-rebuild v2).
