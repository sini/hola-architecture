# `hola` — Evidence Ledger & Reproducible Experiments

Preserved artifacts from the two research workflows
(`hoag-nixpkgs-feasibility` = Phase 1, `hola-full-hoag-evaluation` = Phase 2).
The synthesis docs (`../phase-1-feasibility.md`, `../phase-2-implementation-seed.md`)
state the *conclusions*; this directory preserves the *reproducible evidence* —
the raw structured findings and the agents' actual experiment fixtures.

## Provenance & reproduction

- **nixpkgs rev:** `2f4f625e` (local checkout `~/Documents/repos/nixpkgs`,
  2026-06-23). Floors/numbers are rev-sensitive (the v2 merge path is recent).
- **Run:** `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=out.json nix-instantiate --eval --strict --json <fixture>.nix`,
  with `NIX_PATH=nixpkgs=~/Documents/repos/nixpkgs`. Metric = `nrFunctionCalls` /
  `nrThunks` / `nrOpUpdateValuesCopied` deltas.
- **Caveat:** fixtures are `/tmp` snapshots written by sandboxed subagents; some
  embed absolute `/tmp/...` paths and assume the rev above. They are *provenance
  + reproducible-with-edits*, not a turnkey suite. The clean, durable harness is
  spike **S0** (see `../phase-2-implementation-seed.md` §6), which these seed.

## Layout

| Dir | What |
|---|---|
| `../raw/phase-{1,2}-workflow-result.json` | The complete structured findings (cost models, all candidates, every load-bearing claim with its 3-lens adversarial verdict + file:line evidence). **Richer than the synthesis docs.** |
| `../raw/phase-{1,2}-workflow.js` | The workflow scripts that produced them (reproducible). |
| `cost-decomposition/` | Phase 2 cost experiments (the `hola-exp` set): the A/B/D measurements + the contested HC1 decomposition. |
| `claim-proofs/` | Phase 2 claim fixtures `hc{1..7}_*.nix` + `hc5-test/`. |
| `phase1-cost/` | Phase 1 cost-center / `//`-storm / merge-semantics experiments. |

---

## Phase 1 ledger (claims H1–H7)

| Claim | Headline result | Key fixtures |
|---|---|---|
| **H1** `//`-storm intrinsic | `import <nixpkgs>` + attrNames = **1,756,268 copies** before any output; `lib` alone = **494**; 200-module `evalModules` (no pkgs) = **683 copies / 131K fn-calls** → copies ⊥ module machinery | `phase1-cost/bench_just_import.nix`, `bench_lib_only.nix`, `bench_pkgs_min.nix`, `bench_mod_scale.nix` |
| **H4** read-set not static | `nix-instantiate --parse` AST shows `config.x.${k}` is `ExprSelect`-on-`ExprVar` — defeated by dynamic selects | `phase1-cost/q2parse.nix` |
| **H5** gen built on module system | forcing the ref/option introspection plane fires `evalModules`; the parent/collection plane does not | `phase1-cost/gen_eval_test{2,3,4}.nix` |
| **H7** merge non-replicable | `[normal, mkForce, mkDefault, mkIf false, mkOrder]` → **`["c"]`** (force wins mid-list); `foldLayers` replace → `["n"]`; `mkIf false` → `["base"]` (def evaporates) | `phase1-cost/fold_probe.nix`, `reorder.nix`, `mkif.nix`, `adios_merge_test.nix` |

## Phase 2 ledger (claims HC1–HC7 + constraints)

| Claim | Verdict | Headline result | Key fixtures |
|---|---|---|---|
| **HC1** D-cost decomposition | **REFUTED ×3** | Raw exact (**4,559 fn / 6,500 thunks / 1,911 copies per systemd element, FLAT**) but the "67% hoistable" split is a synthetic artifact; real host is demand-merge-dominated (forcing one leaf = **19 fn/svc**) | `cost-decomposition/realsvc.nix`, `dual.nix`, `dual2.nix`, `mergeload.nix`, `ndecls_scale.nix`, `demand.nix`, `realsvc_opts.nix`, `ident.nix` |
| **HC2** per-host D-hoist | **UPHELD ×3** (conditioned) | Shared-shape engine = **111,159 vs 358,723 fn = 69%**, byte-identical (N=250); shareable only for shape-invariant (`shorthandOnlyDefinesConfig=true`) elements; `extendedPostmark=false` (wrapper lost on extend) | `claim-proofs/hc2_shorthand_soundness.nix`, `hc2_shape_divergence.nix`, `hc2_postmark.nix`, `hc2_name_default.nix`, `hc2-split.nix`, `hc2-floor.nix` |
| **HC3** merge → host verbatim | **REFUTED ×3 → hybrid** | merge is mutually-recursive-with-evalModules, value-shape-dispatched, partial-throws, **positional** (`listOf [1,2]+[3,4]→[3,4,1,2]`; `lines` order-sensitive); `valueMeta` escapes to surface ⇒ **S0 landmine corpus** | `claim-proofs/hc3_l1.nix`, `hc3_order.nix`, `hc3_meta.nix`, `hc3_lattice.nix`, `hc3_interact.nix`, `hc3_attack*.nix` |
| **HC4** v2 dual interface | **REFUTED ×3 → simplify** | every v2 type's legacy arrow = `(self.v2{…}).value`, so one uniform `type.merge loc defs` call suffices; `addCheck`/`nullOr`/`functionTo` have `hasV2=false` | `claim-proofs/hc4_equiv*.nix`, `hc4b.nix`, `hc4c.nix` |
| **HC5** lib-injection | **REFUTED ×2** (the gotcha) | `extendModules` calls the **local** `evalModules` → `lib.extend` bypassed per submodule element (`extendedPostmark=false`); root-level swap works, D path does not | `claim-proofs/hc5-test/probe{2,3,4,4b,5}.nix` |
| **HC6** floors hold | **UPHELD ×3** | bare import = **1,756,265 copies**; real `toplevel.drvPath` = **~12.2M copies / ~4.7M fn**, `check=false` moves copies **−0.2%**, drvPath byte-identical; `_module.check` = **~110,035 fn/level** (cost-center B) | `claim-proofs/hc6_*.nix`; `cost-decomposition/ck_*.json` (B), `cs_*.json` (collect-vs-merge), `ident_*.json` (no per-element dedup) |
| **HC7** niche open | **UPHELD ×2** | no prior art reimplements-merge-keep-compat-faster; closest = a-la-carte PR #148456 (CLOSED, ~40%, stalled on hand-annotation) → hola supplies deps externally from the HOAG graph | (web/source survey; no fixture) |

## Fixtures that seed spike S0 (the parity + landmine corpus)

Reuse directly when building the dual-run harness:

- **L1** whole-attrset-evaporation, **L2** `attrsOf`/`lazyAttrsOf` `mkIf false`,
  **L3** v2 triple + `valueMeta`: `claim-proofs/hc3_l1.nix`, `hc3_meta.nix`,
  `hc3_order.nix`, `hc3_lattice.nix`.
- **shorthand-soundness gate** (per-def shape-invariance): `hc2_shorthand_soundness.nix`,
  `hc2_shape_divergence.nix`.
- **injection-bypass proof** (why you must own `modules.nix`): `hc5-test/probe5.nix`.
- **floor / `check` toggle** (drvPath parity baseline): `hc6_*.nix`,
  `cost-decomposition/ck_*.json`.

## Not preserved here

The full subagent transcripts (~4.4MB JSONL, `.claude/projects/.../subagents/workflows/`)
are the audit trail — left in the session dir, not committed. Recoverable there
until the session is cleaned up.
