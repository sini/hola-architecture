# `gen-rebuild` — finalized operation surface (Phase 1 output)

The rebuilder dimension of Mokhov 2018, as a complete, theory-faithful pure-Nix
gen library. Composes gen-scope (scheduler) + gen-graph (topology oracle). This
is the Phase-2a spec input (see `../PLAN.md`).

**Theory grounding** (all summaries in `~/Documents/papers/den-architecture/`):
Mokhov 2018 (rebuilder taxonomy) · Forgy 1982 (Rete deltas) · Radul 2009
(provenance / retraction) · Arntzenius 2016 (semi-naive fixpoint) · **Acar 2002**
(change propagation, splice, order-maintenance — `reference-catalog/`) ·
**Hammer 2014 Adapton** (demand-driven DCG, dirty/clean, memo —
`reference-catalog/`). **PENDING:** Reps–Teitelbaum–Demers 1983 (formal
`dirtySet` minimality) — no open PDF; to be supplied.

---

## The pure-core / external-shell split (the load-bearing Phase-1 finding)

The rebuilder domain cleanly factors along what pure Nix can and cannot do —
and the line lands exactly on the deferred eval-server track (H6):

- **Pure intra-eval core (feasible now).** The *revalidation* half maps onto Nix
  laziness for free: demand-ordering and "don't recompute the undemanded" are
  what `force` + gen-scope's `_eval` already give. All recompute / cutoff /
  provenance / fixpoint ops live here.
- **Externalized-DCG shell (deferred = eval-server).** The *invalidation* half —
  **amortized `dirty` flags**, **`gc`**, and a **persisted hierarchical trace** —
  needs mutable state *between* `nix eval` invocations. Pure Nix has no
  in-place amortized dirtying and no weak-ref gc; laziness already collects
  unforced thunks within a run. So these ops are *specified* but *realized* only
  with the out-of-language eval-server.
- **Pure-Nix advantage:** purity *enforces Adapton's read-only-inner memo-
  soundness precondition for free* — OCaml-Adapton could not enforce it
  statically (Hammer 2014 fn.1). gen-rebuild gets the soundness gratis; it only
  loses the cheap mutable dirty bit (which purity also forbids).

---

## Operation surface (~18 ops)

### Drivers — the change → propagate axis (Acar's change/propagate split)
| op | theory | hola |
|---|---|---|
| `demand`/`force` — the pull trigger | Adapton (only recompute trigger); seam to gen-scope `self.get` | production |
| `applyDelta` / `batch` — apply input change(s) | Forgy ±tokens · Acar `σ⊕δ`, N changes then 1 propagate | production |
| `propagate` — drain the frontier to quiescence | Acar §4.3 (standalone, *distinct* from override) | production |
| `override` — fused single-change convenience (applyDelta+propagate) | Mokhov dirty-bit; **splice semantics grounded by Acar §4.5/§7** | **B-demo** |
| `retract` — non-monotone delete | Radul `kick-out!` · Forgy `−` · Datafun deletion | production |

### Rebuilder strategies (Mokhov §4.2 + §2.3)
`verify` · `constructive` · `deepConstructive` · `earlyCutoff` — the last now
**per-edge labeled** (Adapton Alg.1 l.12: value stored on each edge, prune
mid-walk, finer than per-node).

### Dependency-graph construction (Acar adg builders — make dep-recording first-class)
`read` / `write` / `mod` (or gen-scope-native equivalents) — `read` records the
(source→consumer) edge; today dep-recording is an implicit byproduct, Acar makes
it a first-class, inspectable primitive. Plus `memo`/`alloc` (Adapton keyed
allocation — stable node identity across runs, prerequisite for swapping/switching).

### Provenance (Radul §6.1 + Acar adg reachability)
`support` · `why` · `affected`.

### Incremental fixpoint (Arntzenius semi-naive + Acar propagate-to-quiescence)
`restabilize`.

### Helper
`dirtySet` — cone minus obsolete-contained minus cutoffs (Acar |Iu|⊆|I|
minimality; RTD-1983 grounding pending).

### Externalized-DCG shell (deferred — eval-server only)
`dirty` / `clean` (Adapton lazy two-phase — amortized *only* with persistence) ·
`gc` (only over the persisted DCG).

---

## Seams required (gen-scope / gen-graph / harness) — S1–S9

| seam | where | for |
|---|---|---|
| **S1** warm-cache eval `{priorResults,recompute}` | gen-scope | `override` (non-negotiable — the relocatability hook) |
| **S2** dep-recording (trace-emitting `self.get`) | gen-scope | verify / provenance / the adg |
| **S3** frontier `dependents` (level-by-level, prunable) | gen-graph | `earlyCutoff` |
| **S4** seeded / delta-frontier fixpoint | gen-graph | `restabilize` |
| **S5** `hashOf` hook (consumer-supplied) | param | verify / constructive / cutoff |
| **S6** order / time-stamp (monotone eval rank + insert-after + splice-span) | gen-scope | **Acar order-maintenance — splice correctness** |
| **S7** containment-span + labeled-edge value store | gen-graph | Acar containment (|Iu| vs |I|) + Adapton per-edge cutoff value |
| **S8** bidirectional edge index (ordered outgoing + unordered incoming) | gen-graph | Adapton demand-ordered propagation |
| **S9** externalized DCG + `gc` | harness / eval-server | the deferred persistence layer |

S1–S5 are intra-eval and pure. S6–S8 are pure but new structure. S9 is the
external shell (eval-server).

---

## Conformance benchmark (Adapton's triple)
`gen-rebuild` must pass **sharing · swapping · switching** — the reuse-correctness
test that distinguishes demand-driven IC from eager total-order IC (which fails
all three and is *slower* than from-scratch).

## Deepest open problems (honest gaps, carry into the spec)
1. **Containment recovery.** Acar's containment is *static* (syntactic trace
   nesting); a Nix demand-driven rebuilder records deps *dynamically* and lacks
   it. Recovering containment from a flat dynamic dep-log — so obsolete
   sub-computations aren't wrongly re-run — is **unsolved** and is the deepest risk.
2. **Trace granularity.** Hierarchical DCT (Adapton — enables the triple) vs flat
   per-key trace (Mokhov). Faithful Adapton needs a *hierarchical* persisted
   trace. Key external-representation decision.
3. **Splice granularity** for a lazy `(nodeId, attr)` store — does Acar's
   O(|affected|) cost bound survive per-attribute granularity over a lazy
   memoized store?
4. **`retract` / arbitrary `dirtySet`** have no clean Acar analogue (write-once
   modifiables; monotone-growing change set) — gen-rebuild generalizations.
5. **Citation honesty:** Acar grounds the *re-execution* axis only (not
   verify/constructive/deepConstructive — those stay Mokhov); "purity" should be
   stated as *persistent closures* (Acar §8), not effect-freedom.

## Minimal-B subset (unchanged)
`override` + `dirtySet` + `affected` + seam **S1**. Acyclic, single-change, pure
intra-eval, dirty-bit, no early cutoff. Demonstrates reuse-across-change.

---

*Phase 1 (theory completion) output. Catalog additions: `reference-catalog/`
`{pdf,markdown,summaries}/{acar-2002-adaptive-functional-programming,
hammer-2014-adapton}`. Surface derived from those + the prior
Mokhov/Forgy/Radul/Arntzenius grounding.*
