# hola Engine E2b — nix-config Fleet Host Parity — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if
> subagents available) or superpowers-extended-cc:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Prove the E1 engine byte-identical on real nix-config fleet hosts — full-surface, **pure**:
re-invoke nix-config's whole `outputs` with the host's nixpkgs-channel input's `.lib` doctored to
`engine.lib` + a lazy self-knot, and `drvEq` `nixosConfigurations.<host>.…toplevel.drvPath`
vanilla≡engine, for **bitstream → blade → cortex**.

**Architecture:** Add `github:sini/nix-config` as a committed (rev-locked) ci flake input. A new
`runDenFleet` adapter re-invokes nix-config's raw `outputs` purely (a declared flake input exposes
`.inputs`/`.outPath`), doctoring the channel input's `.lib` + supplying a lazy `outPath`-carrying
self-knot; a per-host fixture + gating test asserts byte-identity. **Engine (`lib/engine/**`) UNCHANGED**
— one 567a49d engine works for all hosts (`modules.nix`+`types.nix` are byte-identical across the
unstable/master channels, verified).

**Tech Stack:** Nix, gen `mkCi` (`cd ci && nix flake check`), the hola parity harness
(`parity.drvPathGate`, `adapter`, `corpus`). nix-config @ flake-parts/dendritic + den.

**Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-24-hola-engine-e2b-fleet-host-design.md`.

**Empirically proven (spec-review ran the full re-invoke, pure):** bitstream (`channelInput =
"nixpkgs-unstable"`) → `70xb6lxav…-nixos-system-bitstream-…567a49d.drv` byte-identical vanilla≡engine;
blade (`channelInput = "nixpkgs-master"`, SAME engine) → `…-nixos-system-blade-…5e8ca42.drv`
byte-identical. The lazy `self = out // { outPath = nc.outPath; inherit (nc) sourceInfo; }` knot is
load-bearing (bare `self = out` throws on string-coercion; a static carrier throws `overlays missing`).

**Two facts that decide the code (verified):** (1) a declared flake input exposes `.inputs` +
`.outPath` (so `inputs.nix-config.inputs` is pure, no `getFlake`); (2) den `channel` name ≠ nixpkgs
INPUT name — bitstream's den channel is `"nixos-unstable"` but the input to doctor is
`"nixpkgs-unstable"`. The fixture carries **`channelInput`** (the input name), never the den channel.

**Working repo:** `~/Documents/repos/hola` on `main`. Stage specific files by name; NO `Co-Authored-By`;
`nix fmt` touched files (NEVER `lib/engine/vendor/modules.nix`); `git add` new files before
`nix flake check`. Commit hooks auto-push to public `github:sini/hola`.

---

## File structure

| File | New/Edit | Responsibility |
|---|---|---|
| `ci/flake.nix` | edit | Add `nix-config.url = "github:sini/nix-config"`; thread `denFleet = { nixConfig = inputs.nix-config; }` via specialArgs. |
| `lib/corpus/den-fleet.nix` | new | `mk { nixConfig, host, channelInput }` → fx carrying the fleet-run data. |
| `lib/adapter.nix` | edit | `runDenFleet engine fx` — pure full-surface channel-lib doctor + lazy self-knot; export it. |
| `lib/corpus/default.nix` | edit | Register `denFleet` (gate `drvPath`). |
| `ci/tests/den-fleet-parity.nix` | new | Gating: `den-fleet-parity.<host>` (bitstream, then blade, cortex) + a `channel-modules-identity` guard (vendored `modules.nix` ≡ both channels). |

`compose.engineParity` is NOT used (it hardwires `runHost`); the test calls `parity.drvPathGate` directly (as E2a's `den-parity` does).

---

## Task 0: Wire nix-config as a committed ci flake input

**Goal:** `github:sini/nix-config` available + rev-locked + threaded to the corpus.

**Files:** Modify `ci/flake.nix` (+ commit `ci/flake.lock`).

**Acceptance Criteria:**
- [ ] `ci/flake.nix` declares `inputs.nix-config = "github:sini/nix-config"`.
- [ ] The corpus receives `denFleet = { nixConfig = inputs.nix-config; }` via specialArgs (alongside existing `hola`/`nixpkgs`/`denCorpus`).
- [ ] `inputs.nix-config` exposes `.inputs` (with `nixpkgs-unstable`/`nixpkgs-master`) and `.outPath`; existing 39 tests still green; root `nixpkgs` stays 567a49d.

**Verify:** `cd ci && nix flake lock && nix flake check` → 39 pass; `inputs.nix-config.inputs ? nixpkgs-unstable` is true.

**Steps:**

- [ ] **Step 1: Add the input + specialArg.** In `ci/flake.nix` `inputs`: `nix-config.url = "github:sini/nix-config";`. In the `mkCi` `specialArgs`, ADD (preserve existing keys):
```nix
        denFleet = { nixConfig = inputs.nix-config; };
```

- [ ] **Step 2: Verify the load-bearing assumptions + commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake lock )
# confirm nix-config exposes resolved .inputs (pure) + the two channels + outPath:
( cd ci && nix eval --impure --expr 'let f = builtins.getFlake (toString ./.); nc = f.inputs.nix-config; in { hasInputs = nc ? inputs; hasOutPath = nc ? outPath; unstable = nc.inputs.nixpkgs-unstable.rev or "?"; master = nc.inputs.nixpkgs-master.rev or "?"; } ' )
# expect: hasInputs=true hasOutPath=true unstable=567a49d… master=5e8ca42…
( cd ci && nix flake check ) 2>&1 | tail -6     # 39 tests still pass
git add ci/flake.nix ci/flake.lock
git commit -m "feat(ci): add github:sini/nix-config input for the E2b fleet corpus"
```
> If `sini/nix-config` is private and the lock can't fetch, STOP and report — E2b needs it reachable
> (the user said a github ref works; confirm the repo is pushed/public).

---

## Task 1: den-fleet fixture + `runDenFleet` adapter + bitstream gate

**Goal:** The pure channel-aware fleet runner, and the first byte-identity gate (bitstream).

**Files:**
- Create: `lib/corpus/den-fleet.nix`
- Modify: `lib/adapter.nix` (add `runDenFleet`)
- Modify: `lib/corpus/default.nix` (register `denFleet`)
- Create: `ci/tests/den-fleet-parity.nix` (bitstream gate + channel-modules-identity guard)

**Acceptance Criteria:**
- [ ] `runDenFleet vanilla fx` / `… engine fx` each return `nixosConfigurations.<host>` with `.config.system.build.toplevel.drvPath`.
- [ ] `den-fleet-parity.bitstream` asserts `(drvPathGate { a = runDenFleet vanilla fx; b = runDenFleet engine fx; }).identical == true`.
- [ ] `channel-modules-identity` asserts vendored `modules.nix` ≡ `nixpkgs-unstable` AND `nixpkgs-master` `lib/modules.nix` (the E2b-D5 single-engine soundness guard).
- [ ] `cd ci && nix flake check` green; count 39 → 41.

**Verify:** `cd ci && nix flake check` → `den-fleet-parity.bitstream` + `channel-modules-identity` green.

**Steps:**

- [ ] **Step 1: Create `lib/corpus/den-fleet.nix`.**
```nix
{ lib }:
{
  # channelInput = the nixpkgs INPUT NAME to doctor ("nixpkgs-unstable" | "nixpkgs-master"), DISTINCT
  # from the den `channel` name (bitstream's den channel is "nixos-unstable", input is "nixpkgs-unstable").
  mk =
    { nixConfig, host, channelInput }:
    {
      gate = "drvPath";
      denFleet = { inherit nixConfig host channelInput; };
    };
}
```

- [ ] **Step 2: Add `runDenFleet` + `fleetEngineLib` to `lib/adapter.nix`** (read it; it has `run`/`runHost`/`runDenTemplate`/`engines`, and `engineConcern = import ./engine { inherit lib; }`). **Channel-seeded** (load-bearing — verified): the doctored lib is built from the HOST'S OWN channel lib, NOT hola's global `engines.engine` (which carries hola's root-nixpkgs `567a49d` and would substitute a foreign lib → an artificial build, not the host's real one). `runDenFleet` takes a `doctor` fn (`channelLib -> lib`): vanilla = identity (reproduces the host's REAL build), engine = vendored-modules-on-the-channel-lib. Add in the `let`:
```nix
  # Build the engine lib from an ARBITRARY base lib (the host's channel lib), so the vendored body
  # rides the SAME nixpkgs the host really uses. `import ./engine { lib = baseLib; }` re-instantiates
  # the engine module against baseLib (no engine change — the module is `{ lib }:`-shaped).
  fleetEngineLib = baseLib: (import ./engine { lib = baseLib; }).engine.lib;

  # Fleet tier (gate="drvPath"): re-invoke nix-config's RAW outputs with the host's channel input's
  # .lib replaced by `doctor channelLib`, + the lazy outPath-carrying self-knot. Pure: a declared
  # flake input exposes .inputs/.outPath. `self` is the ONE input getFlake omits and the toplevel both
  # string-coerces it (host.nix:391) AND forces self.overlays.default (nixpkgs.nix:16) — the lazy
  # `out` fixpoint carrying outPath/sourceInfo supplies both. `doctor = id` ⇒ the host's REAL build;
  # `doctor = fleetEngineLib` ⇒ the host's build with the engine. Identical iff vendored ≡ channel
  # modules.nix (the channel-modules-identity guard).
  runDenFleet =
    doctor: fx:
    let
      f = fx.denFleet;
      nc = f.nixConfig;
      chan = nc.inputs.${f.channelInput};
      raw = import (nc.outPath + "/flake.nix");
      out = raw.outputs (
        nc.inputs
        // {
          self = out // { outPath = nc.outPath; inherit (nc) sourceInfo; };
          ${f.channelInput} = chan // { lib = doctor chan.lib; };
        }
      );
    in
    out.nixosConfigurations.${f.host};
```
  and add `runDenFleet` + `fleetEngineLib` to the returned `inherit` list.
  > If `inputs.nix-config` lacks `.sourceInfo`, carry the individual lock fields instead (`outPath` plus
  > `narHash`/`rev`/`lastModified` from `nc`); the byte-identity gate is the oracle. `outPath` is the
  > one that's load-bearing (string-coercion). **Verified:** `runDenFleet (l: l)` reproduces the host's
  > real drvPath (`70xb6lxav…bitstream…567a49d.drv`, `z1j54phn…blade…5e8ca42.drv`); `runDenFleet
  > fleetEngineLib` is byte-identical to it on bitstream + blade.

- [ ] **Step 3: Register in `lib/corpus/default.nix`** (mirror `denTemplate`): import `denFleet = import ./den-fleet.nix { inherit lib; };` at top; add:
```nix
  denFleet = {
    inherit (denFleet) mk;
    defaultParams = { };
    gate = "drvPath";
    tier = "parity";
  };
```

- [ ] **Step 4: Create `ci/tests/den-fleet-parity.nix`** (`denFleet` is a specialArg; two-level nesting):
```nix
{ hola, denFleet, ... }:
let
  inherit (hola) corpus adapter parity;
  bitstream = corpus.denFleet.mk {
    inherit (denFleet) nixConfig;
    host = "bitstream";
    channelInput = "nixpkgs-unstable";
  };
  nc = denFleet.nixConfig;
  vendored = ../../lib/engine/vendor/modules.nix;
in
{
  flake.tests.den-fleet-parity.bitstream = {
    expr =
      (parity.drvPathGate {
        a = adapter.runDenFleet (lib': lib') bitstream; # vanilla: identity doctor → host's REAL build
        b = adapter.runDenFleet adapter.fleetEngineLib bitstream; # engine: vendored modules on the channel lib
      }).identical;
    expected = true;
  };
  # E2b-D5: the single 567a49d engine is sound for master hosts ONLY while modules.nix is identical
  # across channels. Assert it, so a future drift is caught before trusting blade/cortex parity.
  flake.tests.channel-modules-identity.check = {
    expr =
      builtins.readFile vendored == builtins.readFile (nc.inputs.nixpkgs-unstable.outPath + "/lib/modules.nix")
      && builtins.readFile vendored == builtins.readFile (nc.inputs.nixpkgs-master.outPath + "/lib/modules.nix");
    expected = true;
  };
}
```

- [ ] **Step 5: Verify + commit.**
```bash
cd ~/Documents/repos/hola
nix fmt lib/corpus/den-fleet.nix lib/adapter.nix lib/corpus/default.nix 2>/dev/null || true
( cd ci && nix flake check ) 2>&1 | tail -8     # den-fleet-parity.bitstream + channel-modules-identity PASS; 41 tests
git add lib/corpus/den-fleet.nix lib/adapter.nix lib/corpus/default.nix ci/tests/den-fleet-parity.nix
git commit -m "feat(corpus): runDenFleet + bitstream fleet parity gate (pure full-surface)"
```
> **If bitstream is NOT byte-identical:** real E2b finding (spec §4). `hola.parity.locate`/the two
> drvPaths localize it. Do NOT silence. Interpret under E2b-D5 (pin identity holds → divergence = a
> real Den/engine lib-escape). Report BLOCKED.

---

## Task 2: blade gate (master channel)

**Goal:** Byte-identity on blade — same machinery, `nixpkgs-master`, complex hardware, no microvm.

**Files:** Modify `ci/tests/den-fleet-parity.nix` (add the blade fixture + test).

**Acceptance Criteria:**
- [ ] `den-fleet-parity.blade` asserts byte-identity (`channelInput = "nixpkgs-master"`, `host = "blade"`).
- [ ] `cd ci && nix flake check` green; count → 42.

**Verify:** `cd ci && nix flake check` → `den-fleet-parity.blade` green.

**Steps:**

- [ ] **Step 1: Add to `ci/tests/den-fleet-parity.nix`** (in the `let`, a `blade` fixture; in the set, the test):
```nix
  blade = corpus.denFleet.mk {
    inherit (denFleet) nixConfig;
    host = "blade";
    channelInput = "nixpkgs-master";
  };
```
```nix
  flake.tests.den-fleet-parity.blade = {
    expr =
      (parity.drvPathGate {
        a = adapter.runDenFleet (lib': lib') blade; # vanilla: REAL blade build (…5e8ca42.drv)
        b = adapter.runDenFleet adapter.fleetEngineLib blade; # engine on the master channel lib
      }).identical;
    expected = true;
  };
```
> blade's REAL drv is `z1j54phn…-nixos-system-blade-…20260622.5e8ca42.drv` (master channel) — the
> channel-seeded runner reproduces it on both arms (verified). The `5e8ca42` suffix is correct here
> (NOT `567a49d`): channel-seeding uses blade's own master lib.

- [ ] **Step 2: Verify + commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake check ) 2>&1 | tail -6     # den-fleet-parity.blade PASS; 42 tests
git add ci/tests/den-fleet-parity.nix
git commit -m "test(fleet): E2b blade gate — master-channel host vanilla==engine"
```

---

## Task 3: cortex gate (master channel + microvm guest)

**Goal:** Byte-identity on cortex — the full monty (master channel + the cortex-cuda microvm guest, the genuine open risk).

**Files:** Modify `ci/tests/den-fleet-parity.nix` (add the cortex fixture + test).

**Acceptance Criteria:**
- [ ] `den-fleet-parity.cortex` asserts byte-identity (`channelInput = "nixpkgs-master"`, `host = "cortex"`).
- [ ] `cd ci && nix flake check` green; count → 43.

**Verify:** `cd ci && nix flake check` → `den-fleet-parity.cortex` green.

**Steps:**

- [ ] **Step 1: Add to `ci/tests/den-fleet-parity.nix`** (cortex fixture + test, same shape as blade with `host = "cortex"`).

- [ ] **Step 2: Verify + commit.**
```bash
cd ~/Documents/repos/hola
( cd ci && nix flake check ) 2>&1 | tail -6     # den-fleet-parity.cortex PASS; 43 tests
git add ci/tests/den-fleet-parity.nix
git commit -m "test(fleet): E2b cortex gate — master-channel + microvm host vanilla==engine"
```
> **cortex is the genuine open risk** (its cortex-cuda microvm guest is a fresh sub-evalModules — it
> should run on the doctored channel lib via the module-arg `lib`, but this is the first time it's
> gated). If cortex diverges where bitstream/blade did not, that localizes the microvm-sub-eval as the
> escape — a real, valuable finding. Report it (spec §4/§7); do NOT silence. The fix (if any) is a
> scoped engine follow-up, not folded into E2b's corpus wiring; blade/bitstream still gate green.

---

## Done criteria (E2b complete)

- `cd ci && nix flake check` green incl `den-fleet-parity.{bitstream,blade,cortex}` (real fleet hosts
  byte-identical vanilla≡engine) + `channel-modules-identity` → **engine hosts real production fleet
  configs byte-identically, across both nixpkgs channels.**
- Engine (`lib/engine/**`) unchanged; `vendor-integrity` still green.
- nix-config-as-input is validation-only (removable; not a long-term hola↔nix-config coupling).

**Then:** Wave D — Den swap (point den's `outputs.nix` lib at the engine, behind this oracle) +
cross-scope sharing (Phase 4.5) + the zen comparison. E3 (external lazy selection + gen-rebuild
incremental, swapped INSIDE the owned body) remains the other open arm.
