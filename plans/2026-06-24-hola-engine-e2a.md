# hola Engine E2a — Den Template Parity Corpus — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if
> subagents available) or superpowers-extended-cc:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Prove the E1 engine byte-identical on a real, unmodified Den config — full-surface: thread
`engine.lib` through Den's `minimal` template's whole flake eval and `drvEq` the host
`toplevel.drvPath` vanilla≡engine.

**Architecture:** Add Den + import-tree as ci flake inputs. A new corpus fixture imports the
template's raw `outputs` function and invokes it with `inputs.nixpkgs.lib` doctored to a given
engine's lib (full-surface); a `runDenTemplate` adapter returns the host eval result; a gating test
asserts the two `toplevel.drvPath`s are byte-identical. **Engine (`lib/engine/**`) is UNCHANGED.**

**Tech Stack:** Nix, gen `mkCi` (`cd ci && nix flake check`), the hola parity harness
(`parity.drvPathGate`, `adapter`, `corpus`). Den's `minimal` template (direct `nixpkgs.lib.evalModules`
seam; host `den.hosts.x86_64-linux.igloo` → `nixosConfigurations.igloo`).

**Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-24-hola-engine-e2a-den-template-design.md`.

**Empirically proven config (the spec-review log is the reference):** template `minimal`, host `igloo`,
path `out.nixosConfigurations.igloo.config.system.build.toplevel.drvPath`, inputs
`{ nixpkgs = nixpkgsFlake // { lib = engine.lib }; import-tree; den }` (NO microvm, NO `self`-knot),
nixpkgs pinned `567a49d`, engine seeded from the nixpkgs **flake** lib (carries `nixosSystem`). Under
that config `vanilla ≡ engine` byte-identical. (The exact host drvPath is **illustrative only** and
varies by den rev — e.g. `…-nixos-system-nixos-26.11…567a49d.drv` at den `5df0987`. NEVER assert a
hardcoded hash; the gate — `drvPathGate{vanilla,engine}.identical` — is the oracle. The host's
`hostName` is `nixos`, so the derivation is named `nixos-system-nixos-…`, NOT `…-igloo-…`; `igloo` is
only the den entity/attr key.)

**Working repo:** `~/Documents/repos/hola` on `main` (linear solo workflow; the approved E1 plan set
this precedent). Stage specific files by name (never `git add -A`/`.`); NO `Co-Authored-By`; run the
gen formatter (`nix fmt`) on touched files before commit (CI does not gate on it), NEVER on
`lib/engine/vendor/modules.nix`. New files must be `git add`ed before `nix flake check` (flake copies
only tracked files).

---

## File structure

| File | New/Edit | Responsibility |
|---|---|---|
| `ci/flake.nix` | edit | Add `den` (pinned) + `import-tree` flake inputs; thread `{ den, importTree, nixpkgsFlake }` to the corpus via specialArgs. |
| `lib/corpus/den-template.nix` | new | The Den-template fixture: `mk` builds an fx carrying the raw-`outputs` runner data (template, host accessor, reconstructed inputs). |
| `lib/adapter.nix` | edit | Add `runDenTemplate engine fx` — invokes the template's raw `outputs` with `inputs.nixpkgs.lib` doctored to `engine.lib`, returns the host nixos eval result (`.config.system.build.toplevel.drvPath`-bearing). |
| `lib/corpus/default.nix` | edit | Register `denTemplate` (gate `drvPath`). |
| `ci/tests/den-parity.nix` | new | Gating: `parity.drvPathGate { a = runDenTemplate vanilla fx; b = runDenTemplate engine fx; }` is `identical` (+ a non-vacuity check reusing the engine vs `_brokenProbe`-style isn't needed; the E1 non-vacuity probe already proves the gate has teeth — but assert vanilla≡engine here). |

`compose.engineParity` is reused only conceptually; den-parity uses `parity.drvPathGate` directly
(engineParity's `drvEq` is hardwired to `runHost`, which imports eval-config; the Den runner is a
distinct path).

---

## Task 0: Wire Den + import-tree as ci flake inputs

**Goal:** Den's template source + import-tree available to the harness, pinned, threaded to the corpus.

**Files:**
- Modify: `ci/flake.nix`

**Acceptance Criteria:**
- [ ] `ci/flake.nix` declares `inputs.den` (pinned) and `inputs.import-tree`.
- [ ] The corpus receives `{ den, importTree, nixpkgsFlake }` (the nixpkgs **flake**, not just its outPath) via specialArgs, alongside the existing `hola` / `nixpkgs` (outPath) args.
- [ ] `cd ci && nix flake check` still green (existing 38 tests unaffected).

**Verify:** `cd ci && nix flake check` → green; `nix eval ci#... inputs.den.outPath` resolves.

**Steps:**

- [ ] **Step 1: Add inputs + thread specialArgs.** In `ci/flake.nix`:
```nix
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
    den.url = "github:denful/den";            # pinned by flake.lock; see note
    import-tree.url = "github:vic/import-tree";
  };
```
and in the `mkCi` call, extend `specialArgs`:
```nix
      specialArgs = {
        inherit hola;
        nixpkgs = nixpkgs.outPath or nixpkgs;        # existing: outPath string for realHost
        # E2a: the Den-template corpus needs the nixpkgs FLAKE (for .lib / nixosSystem) + den + import-tree
        denCorpus = {
          inherit (inputs) den;
          importTree = inputs.import-tree;
          nixpkgsFlake = nixpkgs;
        };
      };
```
> **Note (pin):** committing `ci/flake.lock` pins `den` to its resolved rev (reproducible — that's the
> pin). The proven-green rev is **`5df0987`** (`github:denful/den` HEAD as of 2026-06-16, verified
> byte-identical in plan-review). After `nix flake lock`: (a) confirm `inputs.nixpkgs` still resolves
> to 567a49d (the vendored-body rev — `vendor-integrity` enforces it; `nix flake lock` only fills the
> new den/import-tree nodes, it does not re-float nixpkgs); (b) confirm the locked `den` rev is the
> proven `5df0987` (or, if HEAD has moved and Task 2 diverges, pin `den.url = "github:denful/den/5df0987"`
> using the full rev from `nix flake metadata`). The gate is the oracle.

- [ ] **Step 2: Verify + commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake lock && nix flake check ) 2>&1 | tail -6   # 38 tests still pass
git add ci/flake.nix ci/flake.lock
git commit -m "feat(ci): add den + import-tree inputs for the E2a Den-template corpus"
```

---

## Task 1: Den-template fixture + `runDenTemplate` adapter

**Goal:** A corpus fixture whose `runDenTemplate engine fx` builds the Den `minimal` host under a
given engine (full-surface lib-doctoring) and returns its nixos eval result.

**Files:**
- Create: `lib/corpus/den-template.nix`
- Modify: `lib/adapter.nix` (add `runDenTemplate`)
- Modify: `lib/corpus/default.nix` (register `denTemplate`)

**Acceptance Criteria:**
- [ ] `corpus.denTemplate.mk denCorpus` returns an fx with `gate = "drvPath"` carrying the template/host/inputs data.
- [ ] `adapter.runDenTemplate engines.vanilla fx` and `… engines.engine fx` each return a value with `.config.system.build.toplevel.drvPath` (a real `.drv` path).
- [ ] Doctoring is total: the runner sets `inputs.nixpkgs = nixpkgsFlake // { lib = engine.lib; }` (full-surface), no `self`-knot, inputs `{ nixpkgs, import-tree, den }` only.

**Verify:** `nix eval` (impure) that both `runDenTemplate` runs yield a `…toplevel.drvPath` string ending `.drv`.

**Steps:**

- [ ] **Step 1: Create `lib/corpus/den-template.nix`.**
```nix
{ lib }:
{
  # mk: build the Den-template parity fixture. `denCorpus` = { den; importTree; nixpkgsFlake; }.
  mk =
    {
      den,
      importTree,
      nixpkgsFlake,
      template ? "minimal",
      # per-template accessor: where the host nixos eval result lands in the template's `.config.flake`.
      hostOf ? (out: out.nixosConfigurations.igloo),
    }:
    {
      gate = "drvPath";
      # data the runDenTemplate adapter consumes (it does the engine-lib doctoring):
      denTemplate = {
        inherit den importTree nixpkgsFlake template hostOf;
      };
    };
}
```

- [ ] **Step 2: Add `runDenTemplate` to `lib/adapter.nix`.** It mirrors `runHost`'s role (threads an
  engine through a host eval) but for the Den-template path:
```nix
  # Den-template tier (gate="drvPath"): invoke the template's RAW outputs with inputs.nixpkgs.lib
  # doctored to the engine's lib (full-surface), return the host nixos eval result.
  runDenTemplate =
    engine: fx:
    let
      t = fx.denTemplate;
      raw = import (t.den.outPath + "/templates/${t.template}/flake.nix");
      out = raw.outputs {
        nixpkgs = t.nixpkgsFlake // { lib = engine.lib; };
        import-tree = t.importTree;
        den = t.den;
      };
    in
    t.hostOf out;
```
  Add `runDenTemplate` to the returned `inherit` list.

- [ ] **Step 3: Register in `lib/corpus/default.nix`.** Add:
```nix
  denTemplate = {
    inherit (denTemplate) mk;
    defaultParams = { };          # mk is called with denCorpus at the test site
    gate = "drvPath";
    tier = "parity";
  };
```
  (import `denTemplate = import ./den-template.nix { inherit lib; };` at the top, mirroring the others).

- [ ] **Step 4: Verify + commit.**
```bash
cd ~/Documents/repos/hola
# sanity eval (impure; denCorpus reconstructed from the ci flake inputs):
( cd ci && nix eval --impure --expr '
  let f = builtins.getFlake (toString ./.); np = f.inputs.nixpkgs;
      hola = import ../. { lib = np.lib; };
      denCorpus = { den = f.inputs.den; importTree = f.inputs.import-tree; nixpkgsFlake = np; };
      fx = hola.corpus.denTemplate.mk denCorpus;
      d = (hola.adapter.runDenTemplate hola.adapter.engines.engine fx).config.system.build.toplevel.drvPath;
  in d' ) 2>&1 | tail -3       # expect a /nix/store/...-nixos-system-nixos-...567a49d.drv (hostName="nixos", NOT "igloo")
nix fmt lib/corpus/den-template.nix lib/adapter.nix lib/corpus/default.nix 2>/dev/null || true
git add lib/corpus/den-template.nix lib/adapter.nix lib/corpus/default.nix
git commit -m "feat(corpus): Den-template fixture + runDenTemplate (full-surface lib doctor)"
```

---

## Task 2: Den-template parity gate (the byte-identity proof)

**Goal:** Gating test: the Den `minimal` host `toplevel.drvPath` is byte-identical vanilla≡engine.

**Files:**
- Create: `ci/tests/den-parity.nix`

**Acceptance Criteria:**
- [ ] `den-parity.den-template` asserts `(parity.drvPathGate { a = runDenTemplate vanilla fx; b = runDenTemplate engine fx; }).identical == true`.
- [ ] `cd ci && nix flake check` green; total test count up by 1 (→ 39).

**Verify:** `cd ci && nix flake check` → `den-parity.*` green; independently, the two drvPaths print equal.

**Steps:**

- [ ] **Step 1: Create `ci/tests/den-parity.nix`** (two-level `<suite>.<test>` nesting; `denCorpus`
  is a specialArg from Task 0):
```nix
{ hola, denCorpus, ... }:
let
  inherit (hola) corpus adapter parity;
  fx = corpus.denTemplate.mk denCorpus;
in
{
  flake.tests.den-parity.den-template = {
    expr =
      (parity.drvPathGate {
        a = adapter.runDenTemplate adapter.engines.vanilla fx;
        b = adapter.runDenTemplate adapter.engines.engine fx;
      }).identical;
    expected = true;
  };
}
```

- [ ] **Step 2: Verify + commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake check ) 2>&1 | tail -8     # den-parity.den-template PASS; 39 tests
git add ci/tests/den-parity.nix
git commit -m "test(den): E2a parity gate — Den minimal host toplevel.drvPath vanilla==engine"
```

> **If NOT byte-identical:** this is a real E2a finding, not a thing to silence (spec §4). Use
> `hola.parity.locate { a = …; b = …; }` (value tier) or compare the two drvPaths + the host configs
> to localize WHERE Den escapes the engine. Interpret under spec E2a-D5 (the pin makes a divergence an
> unambiguous Den lib-escape, not modules.nix rev drift). Report the gap; its fix is a scoped engine
> follow-up, NOT folded into this corpus wiring. Do NOT mark Task 2 complete with a red gate.

---

## Done criteria (E2a complete)

- `cd ci && nix flake check` green, including `den-parity.den-template` (Den `minimal` host
  `toplevel.drvPath` byte-identical vanilla≡engine) → **the engine hosts real Den framework eval
  byte-identically.**
- Engine (`lib/engine/**`) unchanged; `vendor-integrity` still green (vendored ≡ 567a49d).
- Push `main` only when the user asks (public `github:sini/hola`).

**Then:** E2b — a nix-config fleet host (flake-parts/dendritic, `inputs.self` knot, its own
nixpkgs-pin alignment): the production-scale, Wave-D-target proof. Separate increment.
