# Synthetic-scale axon fleet + observability harness — design (step 2.0)

> **Status:** design, approved in brainstorming 2026-06-26. Sub-piece **2.0** of the
> comprehensive **open-emit affordability program** (step 2 of the fleet build order). The
> measurement substrate every later piece (S1, S2, Plane 2a, observability) lands on.
> **Date:** 2026-06-26.

## 0. Governing principle (explicit)

**YAGNI is rejected for this program.** Every lever and every conceivable edge case is
first-class; we capture every crumb of performance and observability. The harness is built
so no regime is designed away and every measurement is reachable at fleet scale.

## 1. Why 2.0 exists (the grounding)

Step 1 measured the real-axon open emit (`analysis/experiments/fleet-open-emit/`) and the
follow-on cone-cost probe (axon-02, eval-cache off) decomposed the per-peer cost:

| read | fn-calls | copies | forces |
|---|---|---|---|
| `hostName` (base) | 9.0M | 3.66M | the module-fixpoint base |
| `users.users.frr.uid` (light cone) | 9.2M | 2.68M | base + users closure |
| `systemd.services` names (heavy cone) | 10.5M | 8.32M | base + 123 service defs |
| `toplevel.drvPath` (everything) | 25.8M | 32.3M | base + derivation construction |

Findings that motivate a **scale** harness: (a) the ~9M-fn base is **memoized across
same-system peers** (3-host collect = 1.37× one host in fn; cortex 7-host = 1.45×) — so the
per-peer *increment* is the copies, not the base; (b) the per-peer copies are
**cone-dependent** (light 2.68M vs heavy 8.32M); (c) derivation construction (the 25.8M
jump) is already avoided by open emits. **None of this generalizes to fleet behavior from 3
hosts** — class-sharing's N→K win, S2's cone savings on heavy emits, and the O(N²)
cross-host aggregation only appear at scale. 2.0 builds that scale.

## 2. Decided forks (brainstorming)

- **Fidelity = parametric, default full-axon.** The factory takes a configurable aspect-set;
  default is the real full axon class; reduced sets are reachable for deliberate isolation.
- **Composition = parametric class distribution.** A list of class specs (not a hardcoded
  2-way split); **K (class count) is a measurement variable**; default a realistic-axon mix.
- **Skeleton = full topology.** A synthetic environment + cluster + bgp hub so spoke/k3s/mesh
  aspects are coherent and the real O(N²) closed-aggregation machinery is stressed at scale.

## 3. Components

### 3.1 Host factory (parametric, full-fidelity)
A worktree module consuming a **class-spec list** `[{ name, includes, count, axisOverrides? }]`
with a realistic-axon default (base class + a superclass slice via `services.storage.media-scratch`
+ a couple deliberate variants). Folds (`concatMap`) into `den.hosts.x86_64-linux.axon-synth-NNN`
entities.

- **Per-host axis synthesized from index N** — hostname `axon-synth-NNN`; ipv4 from a generated
  /16; ipv6; thunderbolt loopback ipv4/ipv6 + nsap (unique per index); synthetic `/dev/disk/by-id/…`
  device strings (asserted non-empty only); bgp localAsn — real per-host variance for free.
- **Shared `facter.json`** — one committed synthetic hardware profile, applied via the `facts`
  override on every synth host (same hardware class).
- **`synthFleet.enable` defaults OFF** — real axon-01/02/03 untouched; synth hosts are additive.
- **Class key = sorted `den.aspects.<host>.includes`** (the established class key) — the factory
  records each host's class so the observability layer can partition without re-deriving.

### 3.2 Topology skeleton
A synthetic environment + cluster + one synthetic **bgp hub** so spoke/k3s/mesh resolve. Knobs:
(i) toggle the heavy O(N²) closed aspects (k3s-collect/mesh) for tractable iteration; (ii) flip
the open-emit collect **central-O(N) ↔ per-host-O(N²)** to measure the blow-up deliberately.

### 3.3 Observability — the "every crumb" layer
Exposed **two ways**: Nix-level evaluable attrs `flake.synthFleet.observe.{…}` (data) **and** an
external sweep driver that varies N/K/cone and tabulates → durable reports.

- **Perf** — NIX_SHOW_STATS per eval (`nrThunks`/`nrFunctionCalls`/`nrOpUpdateValuesCopied`/
  `cpuTime`/`maxRSS`) with the base/cone/derivation decomposition; scaling curves vs **N**, **K**,
  **cone-weight**.
- **Forcing** — poison-sentinel force-counter (per-edge: which peers a collect forces) + force-set
  size (scoped ≈ matched, not N). The sentinel makes a non-target peer's config `throw`; a clean
  eval proves it was not forced (the Gate-A technique, generalized to N hosts).
- **Cone (S2)** — declared-cone size, actual forced-cone, savings vs full-config.
- **Class (2a)** — partition (host→class key), K, class sizes, **share ratio**, per-class
  byte-identical parity-gate (drvPath core-injected vs from-scratch), axis/core split.
- **Provenance** — gen-rebuild `why`/`support` trace (zero-recompute) + blast-radius
  (`dependentsFrontier`).

### 3.4 Structure / location
Factory + skeleton + Nix observability module → the **worktree** (`demo/persist-claims-open-emit`,
throwaway, additive to step-1). Sweep driver → scripts. **Durable reports + the baseline N=100
measurement → papers `analysis/experiments/synthetic-fleet/`** (consistent with step-1 evidence).

## 4. Success criteria

1. Generate **N** full-axon-class synthetic hosts across **K** classes (parametric) that **eval to
   real nixosSystem configs without throwing**.
2. The open emit + scoped collect work at **N=100** (a step-1-M1-equivalent at scale).
3. **All observability crumbs measurable** across an N/K/cone sweep: perf stats, force-counts, cone
   sizes, class partition, per-class parity-gate, provenance.
4. A **baseline N=100 measurement captured** to papers (the substrate's reference numbers).

## 5. Open implementation risks (resolved during build, not blockers)

- **Secrets:** synth hosts have no real agenix secrets. Plan = share one dummy secret set /
  synthetic master; **fallback** = disable the secret-requiring aspect for synth hosts if eval
  throws. To be settled empirically in the first build task.
- **Cross-host O(N²) tractability:** 100 full-axon hosts × closed-emit aggregation is O(N²) reads
  (cheap per read, but N²). If N=100 eval is intractable for iteration, the knobs (§3.2) cap it;
  the O(N²) curve is then measured at a sweep of smaller N and extrapolated — and the blow-up is
  itself a recorded finding (the case for gen-graph point-queries over condensation).
- **bgp hub at 100 spokes / keepalived VRRP nodeId range / k3s 100-server cluster:** synth topology
  must produce valid values (nodeId ≤ 255, unique loopbacks/nsap); the factory's index synthesis
  must respect these. Verified in the skeleton task.

## 6. Boundaries

- 2.0 is the **substrate only** — it does not implement S1, S2, or Plane 2a (those are 2.1–2.3,
  each built and measured *on* this harness).
- The synth fleet is **throwaway** (worktree branch, never merged); durable artifacts are the
  papers evidence + reports.
- No den-framework change in 2.0 (the open emit uses shipped `pipe.collect`; den-seam changes are
  2.1+).

## 7. References

- Program framing + the comprehensive decomposition: this session's brainstorming;
  `RESUME-fleet-architecture.md` build order.
- Architecture: `specs/2026-06-25-fleet-eval-sharing-architecture.md` (§4 Tier-1/2, §5 Plane 2,
  §7 soundness, §8a S1–S4, §9 perf contract).
- Step-1 evidence + the cone-cost grounding: `analysis/experiments/fleet-open-emit/`.
- den anchors: `policy-effects.nix:296-346` (pipe API), `resolve.nix:392/393-408/468`
  (config-dep boundary / global flag / hostConfigs B′), `host.nix:258-397` (axis carriers +
  instantiate), `schema/host.nix:392` (facter default). nix-config: `axon-0N.nix:48-64`
  (class includes), `deterministic-uids.nix:136` (frr 978), `policies/pipes.nix` (collect
  policies), `policies/fleet.nix` (scope tree).
- Memory: `project_hola`.
