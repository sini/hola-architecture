# hola Engine — E2a: Den Template as Parity Corpus (full-surface) — Design Spec

> **Status:** approved design, pre-implementation (spec-review loop empirically verified the corrected
> mechanism; pending user review).
> **Date:** 2026-06-24.
> **Increment:** hola Phase 4.2, Wave C, sub-increment **E2a** (first of E2a→E2b; follows E1, shipped @ `github:sini/hola` 5340a70).
> **Repo:** `~/Documents/repos/hola` (`github:sini/hola`).
> **Reuses:** the E1 engine (`adapter.engines.engine` = `mkEngine ./vendor/modules.nix`) UNCHANGED, and `compose.engineParity`'s `drvPath` branch. E2a is **harness-corpus + adapter wiring only — no engine changes.**
> **nixpkgs pin:** `567a49d` (the harness input; the vendored body must match it — §4). **Empirically proven:** `minimal` template + 567a49d + the rev-matched shipped engine → `toplevel.drvPath` byte-identical vanilla≡engine.

## 1. Context & motivation

E1 proved the engine byte-identical on the synthetic/landmine/real-host corpus — but that corpus is
*nixpkgs-shaped* modules. **E2 proves byte-identity on real, unmodified Den configs**, the bridge to
the Wave-D Den swap ("once green, Den's swap is just pointing `outputs.nix` at the engine behind the
oracle"). Decided with the user: **full-surface** (thread `engine.lib` through Den's *entire* flake
eval) and **templates first, then a fleet host** (E2a = a Den template; E2b = a nix-config fleet host).

**E2a** uses Den's **`minimal` template** — the simplest template that (a) uses the direct
`inputs.nixpkgs.lib.evalModules` seam (so lib-doctoring is cleanly total), (b) declares a real Den
host (`den.hosts.x86_64-linux.igloo`, user `tux`) exposed at the clean path
`nixosConfigurations.igloo` with a `system.build.toplevel`, exercising `den.hosts` + `den.aspects`
resolution + Den's host re-instantiation (`den/nix/nixModule/default.nix:11`), and (c) **evaluates
cleanly under the mandatory 567a49d pin** and is byte-identical there. The `microvm` template is
rejected (E2a-D3): its 9p `/nix/store` share generates a `fileSystems."/nix/store".fsType` that
couples to a nixpkgs internal which *throws under 567a49d for vanilla too* — irreconcilable with the
pin. The flake-parts `default` template (`mkFlake`, `inputs.self` knot, `nixpkgs-lib` indirection) is
**deferred to E2b/fleet** — that complexity is fleet-shaped.

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| E2a-D1 | **Full-surface via lib-doctoring** — invoke the template's raw `outputs` with `inputs.nixpkgs.lib` swapped to `engine.lib` | `minimal` is `outputs = inputs: (inputs.nixpkgs.lib.evalModules { modules=[(import-tree ./modules)]; specialArgs={inherit inputs;}; }).config.flake`. Doctoring `inputs.nixpkgs.lib` routes the **entire** Den eval (aspect resolution, the host re-instantiation `evalModules`, the toplevel) through the engine. **Empirically verified total** for this config. |
| E2a-D2 | **Den wired in as a ci flake input** (pinned to an explicit rev), raw `outputs` reconstructed | User-confirmed "wired in, not wrapped." Den has **no flake.lock** (`flake.nix` = `outputs = _: import ./nix`), so pin `den` explicitly in `ci/flake.nix` (do NOT rely on the template's own lock, which pins a different rev). The consumed `den` input is Den's flake outputs ≈ `import (den + "/nix")` (`.flakeModule`, `.lib`, …). Harness supplies `{ nixpkgs, import-tree, den }` (minimal needs no `microvm`, no `self`). |
| E2a-D3 | **Template = `minimal`** (direct-evalModules seam, real `den.hosts.igloo` at `nixosConfigurations.igloo`); NOT `microvm`, NOT flake-parts `default` | `minimal` satisfies the pin (E2a-D5) AND evals cleanly AND is byte-identical (proven). `microvm` is unsatisfiable under the pin (9p `/nix/store` `fsType` throws at 567a49d, vanilla included). `default` = mkFlake + `inputs.self` + `nixpkgs-lib` indirection = E2b-shaped. |
| E2a-D4 | **Gate = `drvPath`**, reuse `compose.engineParity` | `drvEq` on `nixosConfigurations.igloo.config.system.build.toplevel.drvPath`, vanilla-lib vs engine-lib — same oracle tier as E1's realHost. |
| E2a-D5 | **Pin alignment (load-bearing):** the engine's vendored body, the engine's base lib, AND the template's nixpkgs are all `567a49d` | The two `modules.nix` bodies (567a49d vs the template's default rev) **genuinely differ** (218 diff lines: `zipAttrs`→`zipAttrsWith`, the `addDeprecatedWrapped` merge branch). So a 567-bodied engine doctoring a *different*-rev template substitutes a different module system than vanilla → byte-identity would be ambiguous/coincidental. **The byte-identity claim is only meaningful when vendored body ≡ template nixpkgs ≡ 567a49d.** `vendor-integrity` enforces vendored ≡ harness nixpkgs. |
| E2a-D6 | **Engine seeded from the nixpkgs FLAKE lib** (not the raw `lib/` import) | `nixosSystem` is injected by nixpkgs `flake.nix`, not `lib/default.nix`. `mkEngine` extends whatever base lib it is handed, so the runner builds `engine = (import hola/lib/engine { lib = nixpkgsFlake.lib }).engine` and doctors `nixpkgsFlake // { lib = engine.lib }`. **No engine code change** — existing `mkEngine` composes correctly (proven). |
| E2a-D7 | **New corpus concern + test, engine untouched** | `lib/corpus/den-template.nix` (fixture + raw-`outputs` runner, attr path as a per-template field) + `ci/tests/den-parity.nix`. |

## 3. Mechanism (the spine — empirically verified)

```nix
# lib/corpus/den-template.nix  (sketch; the runner + attr path are proven against `minimal`)
{ lib }:
{
  mk =
    { den, importTree, nixpkgsFlake,        # nixpkgsFlake = the 567a49d nixpkgs FLAKE (carries nixosSystem)
      template ? "minimal",
      # per-template: where the host toplevel lands, as a function of the template's `.config.flake`
      hostDrvPath ? (out: out.nixosConfigurations.igloo.config.system.build.toplevel.drvPath),
      extraInputs ? { } }:                   # {} for minimal; { microvm = …; } if a richer template is added
    {
      gate = "drvPath";
      # run: build the template's output under a given engine ({ lib; evalModules }), return host drvPath.
      run = engine:
        let
          raw = import (den + "/templates/${template}/flake.nix");
          inputs = {
            nixpkgs = nixpkgsFlake // { lib = engine.lib; };   # full-surface doctor
            import-tree = importTree;
            den = den;                                          # = den flake outputs (import (den+"/nix"))
          } // extraInputs;
        in
          hostDrvPath (raw.outputs inputs);                     # no self-knot for minimal
    };
}
```

`drvEq` compares `run engines.vanilla` vs `run engines.engine` (both seeded per E2a-D6).
`engineParity` (drvPath branch) is reused via a small `runDenTemplate`-style adapter analogous to
`runHost`. **Proven:** `{ vanilla = dz3ss18g…-26.11-…drv; engined = dz3ss18g…-26.11-…drv; identical = true }`.

## 4. What it proves / the honest unknown (conditioned on the pin)

With the rev-matched pin in force (E2a-D5), E2a proves the engine byte-identical on Den's
**framework-internal** evalModules surface — what E1's corpus never touched: `den.hosts`/`den.aspects`
resolution and Den's host re-instantiation `evalModules`, **all on the engine at once.**

**Honest unknown:** whether doctoring `inputs.nixpkgs.lib` reaches *100%* of Den's eval. If some Den
`lib` does not flow from the doctored `inputs.nixpkgs` — a sliver could escape the engine. The parity
harness *empirically* catches it: a divergent `toplevel.drvPath` localizes (via `parity.locate`)
where Den escapes. **Crucial caveat (E2a-D5):** this leak-detection is only *unambiguous* when
vendored body ≡ template nixpkgs. WITHOUT the pin, a divergence could be pure `modules.nix` rev drift
(a false "leak") rather than a real Den lib-escape. So the pin is not optional — it is what makes a
divergence *mean* "Den escaped the engine."

## 5. Components / files

| File | Status | Role |
|---|---|---|
| `lib/corpus/den-template.nix` | new | The Den-`minimal` fixture + raw-`outputs` runner (doctors `inputs.nixpkgs.lib`; attr path = per-template field). |
| `lib/corpus/default.nix` | edit | Register `denTemplate` (gate `drvPath`). |
| `lib/adapter.nix` | edit (maybe) | A `runDenTemplate engine fx` runner if the fixture's `run` doesn't slot into the existing `runHost`. |
| `ci/tests/den-parity.nix` | new | `engineParity` over the Den-template fixture (drvPath). Gate. |
| `ci/flake.nix` | edit | Add `den` (pinned rev) + `import-tree` flake inputs; `nixpkgs` already `567a49d` (the engine's base + doctor source = this flake lib, E2a-D6). |

Engine (`lib/engine/**`) and `compose.engineParity` are **unchanged**.

## 6. Testing & the gate

- `ci/tests/den-parity.nix` (gating, via `cd ci && nix flake check`): `engineParity denTemplateFx == true`
  (drvPath branch → `drvEq` vanilla vs engine on `nixosConfigurations.igloo.…toplevel.drvPath`).
- The harness is the backstop: if not byte-identical, the test fails and `parity.locate`/`drvPathGate`
  pinpoints the divergence — that output IS the E2a finding (the gap map), interpreted under E2a-D5.

## 7. Out of scope (explicit)

- **E2b** — a nix-config fleet host (flake-parts/dendritic, `inputs.self` knot, its own nixpkgs-pin
  alignment): the production-scale, Wave-D-target proof. Separate increment, separate gate. The
  `self`-knot mitigation belongs there, not here.
- **Richer Den machinery** (delivery slots/`route`/`deliver` at host scale, the `microvm` guest): if
  desired later, add a richer *pin-compatible* template/host as another `denTemplate` fixture variant
  (per-template `hostDrvPath` + `extraInputs` already parameterize this) — but only one whose vanilla
  eval survives the 567a49d pin.
- No engine changes, no selection (E3), no gen-rebuild. If E2a surfaces a real engine gap (a Den
  lib-escape, distinguished from rev drift via E2a-D5), its *fix* is a scoped engine follow-up, not
  folded into E2a's corpus wiring.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Wrong host attr path** (the bug the review caught: `microvm`'s host is at `microvms.<h>`, not `nixosConfigurations.<h>`). | Attr path is a **per-template fixture field** (`hostDrvPath`); for `minimal` it is `nixosConfigurations.igloo.…` (proven). Never hardcode `nixosConfigurations.<host>` generically. |
| **Pin unsatisfiable on the chosen template** (the `microvm` failure). | `minimal` is proven to eval *and* be byte-identical under 567a49d. Any future template variant must be vetted to survive the pin's vanilla eval first. |
| **Engine base lib missing `nixosSystem`** (raw `lib/` import lacks it). | E2a-D6: seed the engine and the doctored input from the nixpkgs **flake** lib. No engine change. |
| **Divergence ambiguity** (rev drift vs real lib-escape). | E2a-D5 pins vendored ≡ template nixpkgs ≡ 567a49d, making any divergence an unambiguous Den lib-escape. |
| **Den pin** — Den has no flake.lock; template's lock pins a different rev than HEAD. | Pin `den` explicitly as a ci flake input (E2a-D2); consume `import (den+"/nix")` outputs shape. |
| **Raw-`outputs` needs a `self`-knot.** | Not for `minimal`/simple-seam templates (no `inputs.self`; proven). The lazy self-knot is an **E2b** concern. |

## 9. References

- E1 spec/impl: `specs/2026-06-24-hola-engine-e1-design.md`; engine `~/Documents/repos/hola/lib/engine/**`, `compose.engineParity`, `corpus/real-host.nix` (the drvPath-fixture pattern E2a mirrors).
- Den: `~/Documents/repos/den` (HEAD `2589d732`); `templates/minimal/flake.nix` (direct-evalModules seam), `templates/minimal/modules/den.nix:6` (`den.hosts.x86_64-linux.igloo`, user `tux`), `den/nix/nixModule/default.nix:11` (host re-instantiation `evalModules`), `modules/outputs.nix` (flake-output aspect wrapper). `microvm` template rejected (9p `/nix/store` fsType vs the pin).
- Empirical seam verification: spec-review eval log (raw-`outputs` invocation, no self-knot, `nixosConfigurations.igloo`, `minimal`+567a49d byte-identical `dz3ss18g…`).
- Memory: `project_hola` (Wave C / E1), `project_den_architecture`, `project_nix_config_migration` (E2b target).
