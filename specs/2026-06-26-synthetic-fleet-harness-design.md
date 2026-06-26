# Synthetic-scale axon fleet + observability harness — design (step 2.0)

> **Status:** design, approved in brainstorming 2026-06-26; **revised after adversarial
> spec-review (all 16 issues folded in — see §8).** Sub-piece **2.0** of the comprehensive
> **open-emit affordability program** (step 2 of the fleet build order). The measurement
> substrate every later piece (S1, S2, Plane 2a, observability) lands on.
> **Date:** 2026-06-26.

## 0. Governing principle (explicit)

**YAGNI is rejected for this program.** Every lever and every conceivable edge case is
first-class; we capture every crumb of performance and observability. No regime is designed
away; every measurement is reachable at fleet scale. A measurement that is *not trustworthy*
(a synthetic artifact) is worse than absent — so the harness's own validity is a first-class
concern (this drove most of the spec-review fixes).

## 1. Why 2.0 exists (the grounding)

Step 1 measured the real-axon open emit (`analysis/experiments/fleet-open-emit/`) and a
cone-cost probe (axon-02, **eval-cache off**) decomposed the per-peer cost:

| read | fn-calls | copies | forces |
|---|---|---|---|
| `hostName` (base) | 9.0M | 3.66M | the module-fixpoint base |
| `users.users.frr.uid` (light cone) | 9.2M | 2.68M | base + users closure |
| `systemd.services` names (heavy cone) | 10.5M | 8.32M | base + 123 service defs |
| `toplevel.drvPath` (everything) | 25.8M | 32.3M | base + derivation construction |

Findings that motivate a **scale** harness: (a) the ~9M-fn base is **memoized across
same-system, same-channel peers** (3-host collect = 1.37× one host in fn; cortex 7-host =
1.45×) — so the per-peer *increment* is the copies, not the base, **but only within one
channel** (across channels the base is re-paid — a distinct regime, §3.2); (b) the per-peer
copies are **cone-dependent** (light 2.68M vs heavy 8.32M); (c) derivation construction (the
25.8M jump) is already avoided by open emits. None of this generalizes from 3 hosts —
class-sharing's N→K, S2's heavy-cone savings, the O(N²) cross-host aggregation, and the
across-channel base re-pay only appear at scale. 2.0 builds that scale.

## 2. Decided forks (brainstorming)

- **Fidelity = parametric, default full-axon.** Configurable aspect-set; default real full
  axon class; reduced sets reachable for deliberate isolation.
- **Composition = parametric class distribution.** A list of class specs; **K is a
  measurement variable**; default a realistic-axon mix (now incl. server/agent roles, §3.1).
- **Skeleton = full topology.** Synthetic environment + cluster + bgp hub so spoke/k3s/mesh
  resolve and the real O(N²) closed-aggregation machinery is stressed at scale.

## 3. Components

### 3.1 Host factory (parametric, full-fidelity)
A worktree module consuming a **class-spec list**
`[{ name, includes, count, channel, role, axisOverrides? }]` with a realistic-axon default,
folded (`concatMap`) into `den.hosts.<system>.axon-synth-NNN` entities. **`synthFleet.enable`
defaults OFF** — real axon-01/02/03 untouched; synth hosts additive.

Parametric **axes** (each first-class, each a sweep dimension):
- **Per-host identity axis, synthesized from index N** — hostname, ipv4 (generated /16), ipv6,
  thunderbolt loopback ipv4/ipv6 + nsap, synthetic `/dev/disk/by-id/…` strings, bgp localAsn.
  *Bounds noted:* keepalived VRRP nodeId ≤ 255; 2-byte private ASN ≤ ~1022 — fine at N=100,
  flagged for beyond.
- **Facter as a PARAMETRIC per-host axis (review #1 — the central fix).** A facter generator
  injects representative hardware-class **drift** (disk serial, MAC, cpu count, **ssh host
  key** — the host key derived as a real `ssh-ed25519` keypair so it yields a **valid age
  recipient** via ssh-to-age, residual-3, else rekey throws). Run in **two declared regimes**,
  both reported: `shared-facter` (one profile = the *invariance ceiling*, a mechanism upper
  bound) and `varied-facter` (realistic drift = the fleet-faithful number). **There is no
  source-taint in pure Nix** (residual-2), so the facter bucket is recovered ONLY by the
  two-regime differential in §3.3 (`varied-diff − shared-diff`), not by inspecting attrs.
- **Channel axis (review #6).** ≥2 channels (e.g. unstable + master) so the
  base-memoization-**breaks**-across-channels regime is reachable; channel participates in the
  class key.
- **Role axis (review #14).** k3s **server vs agent** split (a realistic 100-node fleet = few
  servers + many agents), so server-only cert/etcd O(N²) does not dominate and role is a class
  dimension.

**Secrets (review #10 + residual-3 — no aspect removal, generation is a real step).** Resolve via
a **synthetic agenix master**; each synth host's recipient is the **valid age pubkey** derived
from its facter ssh-ed25519 host key (shared in `shared-facter`, per-host in `varied-facter`).
**Rekeying is a GENERATION step** — the first build task runs agenix-rekey to produce the N
rekeyed secret store paths, or `config.age.secrets.<n>` source paths are absent and the fixpoint
throws (this is config + a CLI generation, not config alone). **Aspect-disable is FORBIDDEN as a
fallback for any cone-bearing or class-defining aspect** (it would change `includes` → change the
class key → corrupt the partition, and shrink the S2 heavy-cone signal).

**Class key = sorted `den.aspects.<host>.includes` + channel + role.** The factory records each
host's class so the observability layer partitions without re-deriving.

### 3.2 Topology skeleton
Synthetic environment + cluster + one synthetic **bgp hub** so spoke/k3s/mesh resolve.

- **Open-emit collect mode is a named config construct (review #13 + residual-7):** `central-O(N)`
  = the consumer aspect on ONE designated collector host (others only emit); `per-host-O(N²)` =
  the consumer on every host via `den.schema.host.includes`. **The O(N²)-open curve is measured
  only on ACYCLIC fan-out reads** — each host's emitted VALUE must be independent of its own
  reciprocal collect (a config-dep collect forces the peer's whole fixpoint, which includes that
  peer's reciprocal collect; a symmetric value-dependency is genuine **infinite recursion, not an
  O(N²) curve**). The truly-mutual (symmetric value-dependent) case is therefore the
  **cycle-rejection test** (assert correctly rejected, not hung), a separate first-class case from
  the measured acyclic curve.
- **Isolate the two O(N²) sources (review #14):** the closed-aspect O(N²) (k3s cert SANs / etcd
  member lists / 100-peer mesh string construction) is measured **separately** from the
  open-emit O(N²), via independent toggles, so the curves don't confound.
- **A deliberate global-flag trigger (review #5):** include one scope-ambiguous config-dependent
  collect (a `collectAll`-shaped open emit) that trips the `resolve.nix:393-408`
  `hasAnyConfigThunk`/B′ path — otherwise S1 (its removal) has nothing to bite on and is
  un-measurable here. Gated behind a knob (off for the scoped-only measurements).

### 3.3 Observability — the "every crumb" layer
Exposed two ways: Nix-level evaluable attrs `flake.synthFleet.observe.{…}` (data) **and** an
external sweep driver. **Every measured eval runs `--option eval-cache false` + a cache-bust
(vary an arg)** (review #4) — a precondition, not optional (a cached eval returns zero stats and
silently passes the sentinel).

- **Perf** — NIX_SHOW_STATS per eval (`nrThunks`/`nrFunctionCalls`/`nrOpUpdateValuesCopied`/
  `cpuTime`/`maxRSS`). **Load-bearing claims rest on the deterministic counters
  (fn/copies); `cpuTime`/`maxRSS` get N repetitions + median/IQR** (review #15). **Per-edge /
  per-peer cost is a DIFFERENTIAL, not a single read (review #2):** isolate the per-peer
  increment via `(N)` vs `(N+1)` and force-one vs force-none diffs (the step-1 method), since one
  global NIX_SHOW_STATS cannot attribute per-edge cost. **The `(N)` vs `(N+1)` diff grows a
  FIXED class** (per-class marginal — with K classes the marginal depends on which class grows).
  Scaling curves vs **N, K, cone-weight, channel-count, role-mix**.
- **Forcing — multi-depth poison sentinels (review #3).** A **value-poison** (peer config value
  `throw`s) AND a **structure-poison** (peer's `attrNames`/key-presence `throw`s), because a
  `tryEval`/`lazyAttrsOf`/`attrNames` reader forces structure without forcing the value. The
  reported quantity = **value-forcing under the throws-OBSERVED ceiling** (explicitly documented;
  presence/structure forcing reported separately, not conflated). **A `tryEval`-wrapped force
  defeats BOTH depths by construction** (it is invisible to value- and structure-poison alike) —
  honestly within the throws-OBSERVED ceiling, stated not hidden. Per-edge: which of N peers a
  collect forces; force-set size (scoped ≈ matched, not N).
- **Cone (S2)** — declared-cone size, actual forced-cone (value + structure), savings vs
  full-config — including a deliberately **host-VARYING open emit** (result depends on the
  reader's ip/asn/loopback) so the **non-shareable** read regime is measured, not only the clean
  class-invariant case (review #7), plus an **empty-cone** emit (review #16).
- **Class (2a)** — partition (host→class key), K, class sizes incl. a **singleton class** (review
  #16), and **two share-ratio numbers reported side by side (reviews #1, #12):**
  - **exact-bucket** — `(sorted includes, channel, system)` identical.
  - **near-class / partial (defined, residual-5; same-(channel,system) only, residual-4)** — a
    clustering CHOICE, reported with its rule: within an identical-(channel,system) group, `base`
    = the **maximal common include-set**; near-class membership = `includes ⊇ base` with
    `delta = includes − base`, `|delta| ≤ threshold`; share credit = the base core, per-host the
    delta. Cross-channel/cross-system pairs are NEVER grouped (the nixpkgs base differs → "shared
    core" would be a fiction).
  - **Axis/core/facter 3-way split via the two-regime differential (residual-2):** pure Nix has
    no source-taint, so the split is recovered from the two facter regimes together —
    `identity bucket = shared-facter diff` (only identity varies), `identity∪facter =
    varied-facter diff`, **`facter bucket = varied-diff − shared-diff`**; `core = total −
    (identity∪facter)`. Neither regime alone yields the 3-way split. **Assumption (stated under
    YAGNI-rejected): no config attr is a joint function of BOTH facter and identity** (else the
    subtraction mis-assigns it).
- **Parity-gate — canonicalized-core drvPath equality (review #8 + residual-1, the blocker fix).**
  Raw cross-host `toplevel.drvPath` is **constant-UNequal** — the derivation name is
  `nixos-system-${hostName}-…` and `/etc/hostname` differs, so identity is baked into the drvPath
  by construction and a raw comparison proves nothing (it also contradicts the axis/core split,
  which buckets identity OUT). The oracle therefore compares a **canonicalized core projection**:
  eval each class rep with its **identity+facter axis attrs overridden to a fixed sentinel**
  (doable in 2.0 by overriding the entity axis attrs — **no Plane-2a injector needed**) and assert
  **drvPath equality of the sentinelized configs**. That isolates the non-identity core = the real
  soundness oracle. drvPath equality proves **output shareability**, NOT eval-work-sharing — **the
  perf-win claim rests on the eval-stat decomposition, never on drvPath.** Budgeted: **one rep per
  class** (a toplevel force is the 25.8M-fn path).
- **Provenance (review #11 — the most speculative crumb).** `why`/`support`/`dependentsFrontier`
  need a gen-rebuild graph, which den eval does NOT produce. 2.0 specifies the wiring = **project
  the emit/collect dependency edges into a gen-rebuild graph** — **nodes = emits + collects,
  edges = collect-depends-on-emit** (a defined, net-new sub-component). If that projection proves
  heavy, provenance is the one crumb that **slips to the 2.4 observability layer** — flagged, not
  silently assumed runnable.

### 3.4 Structure / location
Factory + skeleton + Nix observability module → the **worktree** (`demo/persist-claims-open-emit`,
throwaway, additive to step-1). Sweep driver → scripts. **Durable reports (both facter regimes,
both share-ratio numbers, the scaling curves) + the baseline N=100 measurement → papers
`analysis/experiments/synthetic-fleet/`.**

## 4. Success criteria

1a. Every synth host's **config fixpoint forces without throwing** at N=100 across K classes,
    channels, and roles (the real no-throw bar — NOT forcing 100 toplevels, which would OOM).
    **Force depth specified (residual-6):** `deepSeq` of `config.assertions` + the in-cone option
    subtrees (`systemd`/`networking`/`disko`/`age`) **minus the derivation-building leaves** (stay
    off the 25.8M-fn path) — a shallow `config` force would miss a `throw` buried in
    `systemd.services.<x>.script` or a disko leaf and false-pass.
1b. The open emit + scoped collect **resolve at N=100** (a step-1-M1-equivalent at scale).
2.  **All observability crumbs measurable** across the N/K/cone/channel/role sweep, **with
    eval-cache forced off**: differential per-peer perf, multi-depth force-counts, cone sizes
    (incl. host-varying + empty), exact AND near-class share ratios (both facter regimes), the
    one-rep-per-class drvPath-equality oracle, and provenance (or its documented slip to 2.4).
3.  A **baseline N=100 measurement captured** to papers — the substrate's reference numbers,
    with the shared-facter ceiling and varied-facter realistic figures both reported.

## 5. Open implementation risks (resolved during build, not blockers)

- **Secrets:** synthetic master + shared dummy pubkeys must rekey-eval-resolve; **no
  aspect-disable** (§3.1). Settled empirically in the first build task.
- **Cross-host O(N²) tractability:** 100 full-axon hosts × closed aggregation is O(N²) reads;
  toggles (§3.2) cap it and the curve is swept at smaller N + extrapolated. The blow-up is
  itself a recorded finding (the case for gen-graph point-queries over condensation).
- **bgp hub at 100 spokes / k3s server-vs-agent split / VRRP nodeId ≤255 / unique
  loopbacks+nsap:** the factory's index synthesis must produce valid values; verified in the
  skeleton task.

## 6. Boundaries

- 2.0 is the **substrate only** — it does not implement S1, S2, or Plane 2a (2.1–2.3, each built
  and measured *on* this harness). It *does* include the hooks those need: the global-flag
  trigger (§3.2, for S1), host-varying + heavy cones (§3.3, for S2), the partition + drvPath
  oracle (§3.3, for 2a).
- The synth fleet is **throwaway** (worktree branch, never merged); durable artifacts are the
  papers evidence + reports.
- No den-framework change in 2.0 (the open emit uses shipped `pipe.collect`).

## 7. References

- Architecture: `specs/2026-06-25-fleet-eval-sharing-architecture.md` (§4 Tier-1/2, §5 Plane 2,
  §7 soundness incl. throws-OBSERVED ceiling, §8a S1–S4, §9 perf contract).
- Step-1 evidence + cone-cost grounding: `analysis/experiments/fleet-open-emit/`.
- den anchors: `policy-effects.nix:296-346` (pipe API), `resolve.nix:392/393-408/468`
  (config-dep boundary / global flag / hostConfigs B′), `host.nix:258-397` (axis carriers +
  instantiate), `schema/host.nix:392` (facter default). nix-config: `axon-0N.nix:48-64`
  (class includes), `deterministic-uids.nix:136` (frr 978), `policies/pipes.nix`,
  `policies/fleet.nix` (scope tree).
- Memory: `project_hola`.

## 8. Spec-review fold-in (adversarial review 2026-06-26 — all 16 addressed)

1. **Shared-facter fakes share-ratio** → facter is a parametric axis; two regimes (shared
   ceiling / varied realistic) both reported; axis/core split buckets facter-derived config
   explicitly (§3.1, §3.3). 2. **Per-edge cost not attributable from one stat** → differential
   (N vs N+1 / force-one vs force-none) method specified (§3.3). 3. **Sentinel throws-OBSERVED
   ceiling** → multi-depth value+structure sentinels; measured quantity documented (§3.3).
   4. **eval-cache** → forced off + cache-bust, a precondition (§3.3, §4). 5. **S1 un-measurable**
   → deliberate global-flag trigger (§3.2). 6. **Single-channel** → channel axis ≥2 (§3.1).
   7. **Host-varying reads** → host-varying open emit (§3.3). 8. **drvPath gate** → redefined as
   cross-host equality oracle, one rep/class, perf-win on eval-stats not drvPath (§3.3).
   9. **Criterion 1 ambiguous/intractable** → split 1a (config-fixpoint no-throw) / 1b
   (emit+collect resolve); toplevel forcing budgeted (§4). 10. **Secrets fallback guts class** →
   synthetic master + dummy pubkeys, aspect-disable forbidden (§3.1). 11. **Provenance un-wired**
   → gen-rebuild edge projection specified, may slip to 2.4 (§3.3). 12. **Exact-bucketing
   under-credits near-class** → exact AND near-class share ratios both reported (§3.3).
   13. **central/per-host toggle undefined + cycle risk** → named constructs; mutual-collect cycle
   first-class (§3.2). 14. **k3s/mesh O(N²) confound + role-mix** → isolate closed vs open O(N²);
   server/agent role axis (§3.1, §3.2). 15. **Wall-clock variance** → repetitions + median/IQR;
   load-bearing on fn/copies (§3.3). 16. **Empty-cone / singleton-class** → in the sweep (§3.3).

**Iteration-2 residuals (re-review 2026-06-26 — all folded):** R1 (blocker) **drvPath oracle
constant-false** (identity baked into toplevel.drvPath) → canonicalized-core projection via
identity+facter sentinel override (§3.3 Parity-gate). R2 **facter bucketing has no pure-Nix
source-taint** → two-regime differential `facter = varied-diff − shared-diff` + joint-function
assumption (§3.1, §3.3 Class). R3 **ssh-host-key drift must be valid age recipients + rekey is a
generation step** (§3.1 facter + Secrets). R4 **near-class must be same-(channel,system)** +
R5 **near-class partition defined** (base = maximal common include-set; delta ≤ threshold) (§3.3
Class). R6 **1a force depth** = deepSeq assertions + in-cone subtrees − derivation leaves (§4).
R7 **O(N²)-open measured on acyclic fan-out only**; symmetric = cycle-rejection test (§3.2).
Nits: per-class marginal diff (§3.3 Perf); tryEval defeats both sentinels (§3.3 Forcing);
provenance node/edge model (§3.3 Provenance).
