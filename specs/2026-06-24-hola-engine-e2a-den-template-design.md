# hola Engine — E2a: Den Template as Parity Corpus (full-surface) — Design Spec

> **Status:** approved design, pre-implementation (pending spec-review loop + user review).
> **Date:** 2026-06-24.
> **Increment:** hola Phase 4.2, Wave C, sub-increment **E2a** (first of E2a→E2b; follows E1, shipped @ `github:sini/hola` 5340a70).
> **Repo:** `~/Documents/repos/hola` (`github:sini/hola`).
> **Reuses:** the E1 engine (`adapter.engines.engine` = `mkEngine ./vendor/modules.nix`) UNCHANGED, and `compose.engineParity`'s `drvPath` branch. E2a is **harness-corpus + adapter wiring only — no engine changes.**
> **nixpkgs pin:** `567a49d` (the harness input; the vendored body must match it — §4).

## 1. Context & motivation

E1 proved the engine byte-identical on the synthetic/landmine/real-host corpus — but that corpus
is *nixpkgs-shaped* modules. **E2 proves byte-identity on real, unmodified Den configs**, the bridge
to the Wave-D Den swap ("once green, Den's swap is just pointing `outputs.nix` at the engine behind
the oracle"). Decided with the user: **full-surface** (thread `engine.lib` through Den's *entire*
flake eval, not just the final host) and **templates first, then a fleet host** (E2a = a Den
template; E2b = a nix-config fleet host).

**E2a** uses Den's **`microvm` template** — the simplest template that both (a) uses the direct
`inputs.nixpkgs.lib.evalModules` seam (so lib-doctoring is cleanly total) and (b) defines a real Den
host (`den.hosts.x86_64-linux.runnable-microvm`, exercising `den.hosts` + `den.aspects` + the
microvm guest module) that produces a NixOS `system.build.toplevel`. The flake-parts `default`
template (`mkFlake`, `inputs.self` knot, `nixpkgs-lib` indirection) is **deliberately deferred to
E2b/fleet** — that complexity is fleet-shaped.

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| E2a-D1 | **Full-surface via lib-doctoring** — invoke the template's raw `outputs` with `inputs.nixpkgs.lib` swapped to `engine.lib` | Every simple-seam template is `outputs = inputs: (inputs.nixpkgs.lib.evalModules { modules=[(import-tree ./modules)]; specialArgs={inherit inputs;}; }).config.flake`. Doctoring `inputs.nixpkgs.lib` routes the **entire** Den eval (aspect resolution, delivery-slot `lib.evalModules` re-runs via the module-arg `lib`, the guest toplevel) through the engine. This IS "point outputs.nix at the engine." |
| E2a-D2 | **Den wired in as a harness input** (raw `outputs` reconstruction), NOT a pre-built output consumed | User-confirmed: "wired in is correct, not just wrapped." Harness imports `(import (den + "/templates/microvm/flake.nix")).outputs` and supplies the template's inputs (nixpkgs, import-tree, den, microvm) from its own flake inputs. |
| E2a-D3 | **Template = `microvm`** (direct-evalModules seam, real `den.hosts` toplevel); NOT flake-parts `default` | Cleanest total lib-doctoring + genuine Den machinery + a guest `toplevel`. `minimal` has no host; `default`'s mkFlake/self/nixpkgs-lib indirection is E2b-shaped. |
| E2a-D4 | **Gate = `drvPath`**, reuse `compose.engineParity` | `drvEq` on the guest `…toplevel.drvPath`, vanilla-lib vs engine-lib — same oracle tier as E1's realHost. |
| E2a-D5 | **Pin alignment:** override the template's nixpkgs to the harness's pinned `567a49d` | The engine's vendored `modules.nix` (@ 567a49d) must equal the nixpkgs the template evaluates against, or engine ≠ vanilla *structurally*. The existing `vendor-integrity` gate enforces vendored ≡ harness nixpkgs. The microvm input's `nixpkgs` `follows` the (now-pinned) nixpkgs, so its lib is covered too. |
| E2a-D6 | **New corpus concern + test, engine untouched** | `lib/corpus/den-template.nix` (fixture + the raw-outputs runner) + `ci/tests/den-parity.nix`. Den + import-tree + microvm added as ci flake inputs. |

## 3. Mechanism (the spine)

```nix
# lib/corpus/den-template.nix  (sketch — exact input set confirmed in planning)
{ lib }:
{
  mk =
    { den, importTree, nixpkgs, microvm, template ? "microvm", host ? "runnable-microvm" }:
    {
      gate = "drvPath";
      # runner: build the template's output under a given engine, return the host eval result.
      run = engine:
        let
          rawFlake = import (den + "/templates/${template}/flake.nix");
          # reconstruct the template's inputs; doctor nixpkgs.lib to the engine's lib (full-surface).
          inputs = rec {
            nixpkgs   = nixpkgs // { lib = engine.lib; };
            import-tree = importTree;
            den'      = den;            # the evaluated den flake outputs
            microvm   = microvm;
            self      = out;            # self-knot if the template references inputs.self (lazy)
          };
          out = rawFlake.outputs inputs;
        in
          out.nixosConfigurations.${host};   # exact attr path confirmed in planning
    };
}
```

`drvEq` then compares `(run vanilla).config.system.build.toplevel.drvPath` vs
`(run engine).config.system.build.toplevel.drvPath`. `engineParity` (drvPath branch) is reused by
threading this fixture's `run` through a small adapter (`runDenTemplate`) analogous to `runHost`.

## 4. What it proves / the honest unknown

E2a proves the engine is byte-identical on Den's **framework-internal** evalModules surface — what
E1's corpus never touched: `den.hosts`/`den.aspects` resolution, the delivery-slot `extendModules`
re-instantiation (`route.nix:272`, `deliver.nix:271`), and the guest toplevel, **all on the engine
at once.**

**Honest unknown:** whether doctoring `inputs.nixpkgs.lib` reaches *100%* of Den's eval. If Den (or
microvm.nix) reaches a `lib` that does not `follow` the doctored `inputs.nixpkgs` — a sliver could
escape the engine. **This is a feature, not a risk:** the parity harness *empirically* catches any
leak — a divergent `toplevel.drvPath` localizes (via `parity.locate`) exactly where Den escapes the
engine. E2a is therefore either byte-identical (proving full coverage end-to-end) or a precise map
of the gap to close. A non-vacuity check is inherited (the engine is a genuinely distinct evaluator;
E1's `non-vacuity` probe already proves the gate has teeth).

## 5. Components / files

| File | Status | Role |
|---|---|---|
| `lib/corpus/den-template.nix` | new | The Den-template fixture + the raw-`outputs` runner that doctors `inputs.nixpkgs.lib`. |
| `lib/corpus/default.nix` | edit | Register `denTemplate` (gate `drvPath`, tier `both`/`parity`). |
| `lib/adapter.nix` | edit (maybe) | A `runDenTemplate engine fx` runner if the fixture's `run` doesn't slot into the existing `runHost`. |
| `ci/tests/den-parity.nix` | new | `engineParity` over the Den-template fixture (drvPath). Gate. |
| `ci/flake.nix` | edit | Add `den`, `import-tree`, `microvm` flake inputs (den pinned to a rev; nixpkgs already `567a49d`). |

Engine (`lib/engine/**`) and `compose.engineParity` are **unchanged**.

## 6. Testing & the gate

- `ci/tests/den-parity.nix` (gating, via `cd ci && nix flake check`): `engineParity denTemplateFx == true`
  (drvPath branch → `drvEq` vanilla vs engine on the guest `toplevel.drvPath`).
- The harness is the backstop: if not byte-identical, the test fails and `parity.locate`/`drvPathGate`
  pinpoints the divergence — that output IS the E2a finding (the gap map), not something to silence.

## 7. Out of scope (explicit)

- **E2b** — a nix-config fleet host (flake-parts/dendritic, `inputs.self` knot, its own nixpkgs-pin
  alignment): the production-scale, Wave-D-target proof. Separate increment, separate gate.
- No engine changes, no selection (E3), no gen-rebuild. If E2a surfaces an engine gap, that gap's
  *fix* is a scoped follow-up (engine work), not folded into E2a's corpus wiring.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Raw-`outputs` invocation needs a `self`-knot / exact input set.** | Lazy self-knot (`out = rawFlake.outputs (inputs // { self = out; })`); the exact input set is confirmed in planning by reading the template + den flake. The harness fails loudly on a missing input. |
| **Doctoring doesn't reach all of Den's eval** (a lib escapes). | Treated as a finding, not a failure (§4): the drvPath diff + `parity.locate` map the gap. |
| **Pin drift** — template nixpkgs ≠ vendored 567a49d. | E2a-D5 overrides the template nixpkgs to 567a49d; `vendor-integrity` enforces vendored ≡ that input. |
| **Exact toplevel attr path** (`nixosConfigurations.<host>` vs `den.hosts.<sys>.<host>.config`). | Confirmed in planning by reading the microvm template's output shape; the runner returns the host eval result and `drvEq` reads `.config.system.build.toplevel.drvPath`. |
| **microvm.nix as an input** (eval-time module). | drvPath eval only (no build), so substituters/caches are irrelevant; microvm's nixpkgs `follows` the pinned input. |

## 9. References

- E1 spec/impl: `specs/2026-06-24-hola-engine-e1-design.md`; engine at `~/Documents/repos/hola/lib/engine/**`, `compose.engineParity`, `corpus/real-host.nix` (the drvPath-fixture pattern E2a mirrors).
- Den: `~/Documents/repos/den` (HEAD `2589d732`); template `templates/microvm/flake.nix` (`outputs = inputs: (inputs.nixpkgs.lib.evalModules {…}).config.flake`), `templates/microvm/modules/runnable-example.nix` (`den.hosts.x86_64-linux.runnable-microvm`), `modules/outputs.nix` (the flake-output aspect wrapper), delivery-slot re-runs `route.nix:272`/`deliver.nix:271`.
- Memory: `project_hola` (Wave C / E1), `project_den_architecture`, `project_nix_config_migration` (E2b target).
