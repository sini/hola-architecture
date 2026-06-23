# cortex eval profile — the premise-correcting measurement (2026-06-23)

Profiled the real validation target: building `cortex` (primary workstation) in
`~/Documents/repos/sini/nix-config` takes ~50s of `nix eval` (35s on the profiling
box, cold). Goal: decompose it to find hola's *attackable* slice before designing
the engine. Method: `NIX_SHOW_STATS` deltas, `nix eval --no-eval-cache`,
derivation-free leaf (`config.networking.hostName`) vs full
`config.system.build.toplevel.drvPath`. Raw stat JSONs alongside this file.

## Measurements

| id | what | fn-calls | copies | thunks | wall |
|----|------|---:|---:|---:|---:|
| C | dendritic/den **assembly** (`nixosConfigurations` attrNames, no host) | 8.28M | 10.24M | 9.19M | 1s |
| M1 | host module fixpoint (cortex `hostName`, no derivations) | 9.01M | 14.74M | 10.20M | 2s |
| G1 | host + **guest** (`cortex-cuda`) module fixpoint | 9.69M | 18.35M | 11.18M | 2s |
| A | **whole fleet** (7 hosts' `hostName`, one eval) | 13.10M | 35.36M | 15.79M | 3s |
| B1 | formatter, 1 system | 8.95M | 14.74M | 10.39M | 3s |
| B4 | formatter, **4 systems** | 11.11M | 39.11M | 14.42M | 12s |
| M3 | full **toplevel.drvPath** (the build) | **40.52M** | **235.77M** | 65.29M | **35s** |
| — | `_module.check` delta (M3 − check=false) | −86K (−0.21%) | ~−19K | — | — |

## What each axis says

- **M3 is ~94% intrinsic.** M3 − M1 = +31.5M fn / **+221M copies** / +33s = derivation
  construction (`mkDerivation` + overlay `//` + pkgs splicing). Wall is **GC-bound**
  on 235M copies / 6 GB RSS. Untouchable by any pure-eval module reimplementation.
- **Module machinery = ~22% of fn-calls but only ~6% of wall.** The whole module
  fixpoint (assembly + host) is ~9M fn / 2s of 35s.
- **`_module.check` (B) = 0.21%.** Negligible at scale.
- **The guest is not a hidden slice** — +0.68M fn / sub-second; its cost to the
  toplevel is its own (intrinsic) derivation construction.
- **Multi-HOST (A) is already shared by Nix** — 7 hosts ≈ 1.45× one host. Thunk
  memoization shares system-independent work across same-system hosts in one eval.
  *Not a hola win.*
- **The dendritic ASSEMBLY (C) is the one clean attackable module-machinery cost** —
  8.28M fn / 1s = ~92% of the single-host module fixpoint. import-tree imports
  *every* module every eval; the host config adds only ~0.73M fn. hola's *external
  lazy module selection* (assemble only what a host needs) is the lever here. Real
  but ~1s, and shared across hosts in one eval (matters most for single-host
  iterative eval / CI / tooling).
- **Per-SYSTEM re-payment (B) is pkgs-import-bound, not module-bound** — each added
  system ≈ +0.72M fn but +8M copies / +3s, dominated by re-importing `pkgs` per
  system (intrinsic `//`-storm × N). nix-config's perSystem is lean, so the
  adios-flake-style win is small here.

## Verdict — the pivot

**cortex's ~50s is an EVALUATOR / derivation-construction problem, not a
module-system problem.** No pure-eval module reimplementation (hola, zen, adios)
can move it. zen's 3–10× and adios-flake's ~30% were measured on package-free /
output-heavy workloads; on a real derivation-heavy host the same machinery win is
single-digit-% of wall.

This relocates hola's value (see `../../phase-2-implementation-seed.md` and the
project memory):

- **hola's case is its NON-perf properties** — the graph model, sound incremental
  override (den's documented context-threading pain), located cycles, no-throw
  accumulating blame, inspectable composition, external lazy selection. Validate vs
  zen on incrementality / complexity / correctness / parity — **not** wall time.
  Drop "faster than `lib.evalModules` on real configs" as a headline claim.
- **Perf niche (narrow but real):** the ~1s dendritic assembly + module/output-heavy
  flakes + CI/tooling eval — not single-host builds.

## FOLLOW-UP (deferred — separate track)

cortex's ~50s belongs to the **evaluator layer**: spike **Lix** and/or
**Determinate parallel Nix eval** (parallel GC + string reuse vs the 235M-copy
GC bottleneck). Both keep `lib.evalModules` verbatim, need ~no new code, and attack
the actual bottleneck. Decoupled from hola; revisit as its own effort. The cheap
first experiment: re-run cortex `toplevel.drvPath` under Lix, diff wall vs the 35s
baseline here.
