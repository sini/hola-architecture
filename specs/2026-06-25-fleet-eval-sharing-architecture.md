# den-hoag × hola × gen — Fleet Evaluation Sharing & Distributed Config Queries — Architecture

> **Status:** architecture, grounded on the real fleet (workflow `weqp366dj`) and **gate-validated (workflow `wh0ygg53t`): all three gates GREEN** — Gate A (boundary closeable, gate-pass-constrained), Gate B (Plane 2a eval-work-sharing PROVEN on real axon-02/03, byte-identical), Plane 1 (works at zero force). The den-hoag quirk/attribute-eval **seam is designed (§8a, S1–S4)**. Supersedes the bolt-on framing of the E3c-C1 spec (retained as the negative record: per-host *discovered*-boundary sharing is net-negative). This is the **declared**-boundary, den-hoag-entrypoint design.
> **Date:** 2026-06-25.
> **Objective (user):** for a nix-config describing **100s–1000s of hosts**, (1) **share evaluation** across hosts and (2) **answer distributed config questions** (k8s-plane membership, peer IPs/SANs, BGP graph, claim/provide, IP-conflict, blast-radius) **without full-evaluating the fleet**.
> **End-state (user):** as den moves to **den-hoag**, den **controls the flake entrypoint** and **hola is integrated end-to-end** — den-hoag is the fleet evaluator, hola is the per-node nixpkgs-module engine, gen is the primitive substrate.

## 0. The value test (what this work is for)

**Closed (entity-record) emits need none of this — each host's entity record is independently evaluable, so closed cross-host relationships are pure data aggregation with zero eval; den does them today.** The *entire* value of this architecture is making the **OPEN emit — config-dependent cross-host relationships, where host A's relation reads host B's *resolved config*** — affordable at fleet scale. That capability den already ships (`{ host, config, … }` emits resolved against peer configs) but nix-config keeps **dormant**, because reading peer config across the fleet was the blow-up. So every mechanism below is judged by one test: **does it make the open emit affordable?** The class-core eval-sharing, the cone-expander, and the declared edges all earn their place only because the open emit reads peer config and they make that read cheap (cone-restricted) and shared (once per class). The closed-query "plane" is the solved baseline, not a deliverable.

## 1. The one idea

C1 failed because it tried to **discover** the host-invariant subset of a config by probing an eval it did not own (per-host sentinels = O(N) proof, net-negative, unsound on non-forcing channels). The fix is not a better probe — it is to stop discovering and start **declaring**, which is possible precisely because **den owns the eval**:

- den's host/aspect structure **declares the class** (the shared module-set) and the **per-host axis** (the ~7 entity fields that vary).
- den's quirk/pipe structure **declares the open/closed boundary**: an emit `{ host, environment, ... }` is closed (pipeline-parametric, class-shareable); an emit `{ host, config, ... }` is open (reads peer config). The boundary is literally `(functionArgs emit) ? config` (`resolve.nix:392`).

A **declared** boundary needs no O(N) discovery — only an O(K) (per-class) **validation** that the declaration is honest, which is exactly what hola's byte-identical parity gate already does. That single move flips the economics from net-negative to **N-independent net-positive**, and it is sound by construction for the throws-OBSERVED subclass.

## 2. Evidence base (measured on real axon — do not overclaim)

- **Cost-center:** ~94% of cortex's ~36s eval is **derivation construction** (den itself 2.8%, splicing off on native). That cost-center is what must move off the per-host axis.
- **It is host-invariant.** Across the clean class `{axon-02, axon-03}`: k3s package drvPath **byte-identical**, `system.path`/kernel byte-identical, `systemd.units` 241/255 = **94.5%** identical, `environment.etc` 167/176 = **94.9%** identical, full toplevel build-closure Jaccard **99.22%** (43/11029 = 0.39% diverge). **Every** divergent item is attributable to the per-host identity/network/secret axis; **zero** nixpkgs/workload drv diverges for a compute reason.
- **Honest figures:** quote **94–95% (den-layer, per-unit/per-etc)** as the real number; the 99.22% is inflated by trivially-shared nixpkgs. The relocation is `N×11029 → 1×10986 core + N×(~43 leaves + ~10 aggregation roots)` ⇒ ~N-fold reduction of the dominant cost, N-independent core.
- **THE load-bearing caveat — now ANSWERED on the real seam (Gate B).** drvPath equality alone proves only *output* shareability; but the Gate-B force-count **demonstrated eval-WORK sharing** on real axon-02/03 (`CORE-FORCED=1` vs reconstruct `=2`, byte-identical) via `mkForce`-injection at `extendModules` (§5 / §8a S3). So the win is realized intra-process for the proven projection. *Still bounded:* proven on one class-invariant projection (`system.path`), not yet the full core; and **cross-invocation** sharing remains the net-new keystone (Plane 2b).
- **Irreducible:** ~10 aggregation roots (`etc`, `system-units`, `activate`, `toplevel`) re-aggregate per host by construction — never shared; the win is the **sub-root closure**. Two ucode drvs diverge unexplained (~0.018%) — divergent set is ~99.96% network+identity, not 100%.

## 3. The class (axon) — shape

- **Class key = the sorted aspect-include set** (`den.aspects.<host>.includes`), **NOT the hostname prefix.** `axon-02`/`axon-03` are a clean class (byte-identical ~13-aspect lists, `axon-0N.nix:48-63`). `axon-01` carries `+services.storage.media-scratch` (`axon-01.nix:60`) ⇒ a distinct **super-class** = core + `media-scratch` delta. Keying on `axon*` would silently fold a structural variant into the shared core and **corrupt it**.
- **Per-host axis = a fixed-shape ~7-field record** (all `host.nix` options, `identity=false`): `hostname`; `ipv4/ipv6` (`:258-283`); thunderbolt loopback `ipv4/ipv6 + nsap` (`:378-386`); 2 disk `device_id`s; `facter.json` (`:392`, identical top-level schema, value-only deltas); per-host agenix-rekey secrets (`:391`, **identical secret-name set**, per-host ciphertext). The 43 divergent leaf derivations are **pure functions of this record**; it feeds only cheap config leaves (k3s flag strings, FRR/nftables config, disko device strings, secret paths) — **never package construction.** This is the homogeneous-class condition.
- **Cluster scope is already shared:** ~40 k8s aspects (`clusters/axon.nix:72-120`: cilium/argocd/cert-manager/longhorn/cnpg/prometheus/media) eval **once at cluster scope** and apply out-of-band via argocd — already off every host's toplevel. The heaviest workload eval is not on the per-host axis at all.

## 4. Plane 1 — Distributed-query (O(touched)) — TWO TIERS

Distributed config questions split by what they read:

**Tier 1 — entity-record (closed) — the SOLVED BASELINE, not a deliverable.** Membership, peer IPs/SANs, BGP graph, aspect topology, claim/provide of *entity* data — answerable from the ~7-field host entity record via **pipeline-parametric** quirks (`{host,environment,…}`) + `pipe.collect`/`collectAll`, ZERO nixos force (200-host query forces **0** toplevels). **Each entity record is independently evaluable — den does this today; hola/gen/den-hoag add nothing here.** It is listed only to draw the line against Tier 2.

**Tier 2 — config-referencing (open) — forces the source host's MODULE-EVAL slice, NOT the toplevel.** Some claims read the *resolved* config — e.g. a **persist claim for external backup referencing `config.users.users.<svc>.uid` for ownership**. This is an open `{host,config,…}` emit and **cannot** come from the entity record. But it is far cheaper than a build, and the architecture makes it affordable three ways (all measured on real axon, `/tmp/hola_tier2.nix`):
- **(a) module-slice, not derivation-construction.** Reading a config *value* (uid/gid/port) forces that host's module merge + the value's cone — **not** the 94% derivation-construction cost-center (no drvPath). Measured: real axon uids resolve to ints fast (`acme=976`, `frr=978`, …), no toplevel. So a Tier-2 *value* read ≈ the ~6% module slice per touched peer, not a full toplevel. (A Tier-2 read of a *derivation*/store-path — e.g. a rendered config file — additionally pays that one drv.)
- **(b) per-edge scoped, or LOCAL.** If the persist claim is consumed on the *same* host (host backs itself up), it is a LOCAL config emit → den's `markConfigThunk` deferred-local (`class-module.nix:157-168`) → resolved in the host's own evalModules (which runs anyway) → **zero** extra eval. A *central* backup collecting all hosts' claims is cross-host: Gate-A laziness forces only the **collected** peers (`/tmp/d5_lazy_probe.nix`), and the §8a-S2 lint forbids the unscoped `collectAll (_:true)` shape that would force everyone.
- **(c) class-shareable when deterministic.** Measured: axon's shared-user uids are **byte-identical across axon-02/03** (`true`) — the `deterministic-uids` aspect makes ownership class-invariant. So the uid resolution lives in the class core (Plane 2) → resolved **once per class**, shared; only the per-host *data path* (the identity axis) is per-member. The §8a-S4 `pipe.reads` declaration bounds the cone; the O(K) parity gate **validates** the value really is class-invariant (deterministic ⇒ yes; a host using non-deterministic allocation would diverge and the gate would force it per-host).

Tier 2 is exactly the "export quirk pipes eval'd with source-host config" capability — supported, bounded (module-slice + scoped + class-shared), and the §8a seam (S2 cone-expander + S4 declared reads) is what keeps it from degrading to the fleet blow-up.

- **Substrate (all shipped):** `gen-graph` = topology oracle (one fleet accessor over the host registry; claim/provide/network/route/k8s-membership as **separate edge maps** combined by `unionEdges`/`compose`; **point queries** `canReach`/`dependentsOf`/`dependentsFrontier` = O(reachable)). `gen-derive` = relationship rules (claim/provide/route/membership as `mkRule` + stratified phases + fixpoint — already powers den's claim/provide aggregation; distinct identity per relation). `gen-scope` selective materialization (`subtreeOf`/`allNodesWhere`/`nodesOfType`). `gen-rebuild` **provenance** (`why`/`support`, pure trace read, **zero recompute**) answers "would changing host X touch host Y" without evaluating either.
- **Scope discipline:** distinguish `collect` (siblings = same environment, within-plane) from `collectAll` (fleet-wide) — it bounds the touched set. Avoid `gen-graph.condensation` (closure-based **O(n²)**, a ceiling at 1000s of hosts) for global ops; rely on point-query selectivity (verified sufficient).
- **Correction to prior belief:** "network fabric / connect kind 0 / unified claim engine" are **spec concepts (papers), not in code**. Today's claim/provide **is** `pipe.collect` aggregation over quirks (`policy-effects.nix:296-346`). The query plane builds on that reality.

**The deliverable here is Tier 2, not Tier 1.** Tier 1 already works on shipped den; the work only matters where it makes Tier-2 (open, config-referencing) relationships affordable — which is the same class-core sharing (§5) + cone-expander (§8a S2) the eval-sharing arm builds. So Plane 1's *novel* surface and Plane 2 are one effort viewed from two ends of the open emit, not independent planes.

## 5. Plane 2 — Class-core eval-sharing (the perf lever)

Partition the fleet by **class key** (§3). Per class, evaluate the **archetype core once** (the ~10986 host-invariant drvs), freeze it to a **plain serializable projection**, and inject it across the N members; per member, re-evaluate only the ~43 axis-derived leaves + the ~10 aggregation roots.

- **Injection seam:** `host.instantiate` (`host.nix:397`, `instantiate = resolvedChannel.nixosSystem`). Because **den-hoag owns this**, it can evaluate the class core in one fixpoint (no axis values) and thread it into each member's instantiate — rather than calling `nixosSystem` N times from outside (the E2b doctoring/self-knot disappears).
- **The projection (open decision D2):** the value crossing the boundary must be **plain + serializable** — a `drvPath`/out-path projection, **never the config attrset** (function-pervasive ⇒ content-hash null ⇒ always-dirty; `gen-rebuild` hard requirement). A query-only projection and a build-reconstruction projection differ; choose per use.
- **Two tiers:**
  - **2a — intra-process (the measured win) — INTRA-EVAL ONLY — Gate-B PROVEN on real axon.** Within **one** `nix build .#fleet` eval, the class core is one thunk shared across members. This is the *only* sense in which 2a "shares eval across hosts" — it does **nothing** for the cross-run CI/dev-loop (that is 2b, deferred). **PROVEN (not synthetic, not drvPath-equality):** on real axon-02/03, `mkForce`-injecting the class-invariant projection via `extendModules` at the `instantiate` seam (§8a S3) shares **eval work** — `CORE-FORCED=1` across two distinct member fixpoints vs reconstruct baseline `=2`; injection honored without recompute (`REAL-DEF-FORCED=0`); byte-identical to from-scratch (`a02-core→a03 system.path == a03`, `z81p0vvk…`). This *answers* §2 caveat 2 (output-shareability ⇒ now demonstrated work-sharing) on the real seam — the exact `wf_c2hoist` mistake, avoided. **BOUND:** proven on **one** class-invariant projection (`system.path` — a sub-root closure), not yet the full ~11k-drv core; build 2a = extend this to the full class-invariant cone (every primitive exists; den-hoag supplies the eval structure). Aggregation roots stay per-member (§10).
  - **2b — cross-invocation (the net-new KEYSTONE; deferred).** Persisting the class core across runs (the CI/dev loop) is the genuinely unbuilt piece: **`gen-rebuild` threads `gen-scope` as `scope` but never consumes it; the `evalWarm` warm-cache bridge was found unsound and dropped; cross-host result-sharing is deferred (`FUTURE_WORK.md`).** IFD does **not** memoize eval; recursive-nix re-evals pkgs per unit (catastrophic). So 2b is an **explicit net-new component to specify** (a content-addressed cross-eval store of plain projections), not an assembly of existing wiring. Do not assume it present.
- **`gen` mapping:** `gen-scope evalWarm(isClean=(id: id==coreId), priorResults=frozen-core-leaves)` is the inject seam — but it warm-serves **leaf values only** (children/derived always recompute; `eval==evalWarm-off` byte-identical by default). `gen-rebuild build{}.store` (flat id-keyed plain-value map) is the relocatable core payload.

## 6. Plane 3 — Incremental / affected-set

- **Data change** (a host's axis value: new IP, rekeyed secret, facter delta) → `gen-rebuild override`/`affectedSet`/`propagateEager` (cut-heavy O(|AFFECTED|+frontier) via `gen-graph coneRank`+`directDependents`; **edges fixed**).
- **Topology change** (a host adds/removes an aspect ⇒ **changes its class key**, joins/leaves a plane) → `gen-rebuild applyEdgeDelta`/`retract` + **re-partition the class key**. Using `override` for a module-set delta is **unsound** — structural divergence must invalidate the class key, never be injected as a value (e.g. `media-scratch`'s nfs-export keys forked axon-01).
- `dependentsFrontier` = prunable blast-radius that stops at plane boundaries — the "what re-evals if I change the cluster CA" answer, bounded.

## 7. Soundness (the bound that governs all three planes)

Class-keyed injection is **sound for throws-OBSERVED reads** (plain reads, `if`/`mkIf`, comparison, interpolation, `or`). It is **unsound for non-forcing channels** with **no pure detector**: `tryEval`-catch, presence/`?`/`attrNames` over a delta-added key, `lazyAttrsOf`/raw-`attrs` (the facter import is `lazyAttrsOf`). Consequences baked into the design:

1. **The hola byte-identical parity gate is the validation oracle** — per class (O(K)), assert the injected-core member drvPaths `==` the from-scratch member drvPaths. A non-forcing channel that reads an injected value surfaces as a drvPath diff. This is the C1 sentinel/gate **repurposed from per-host discovery to per-class validation** (cheap, sound backstop). At production (hola-only) this gate is the only net — so the validated class set is the contract. **RE-VALIDATION TRIGGER (soundness-critical):** the validation is point-in-time, so **any class member's config change must re-run the O(K) gate before the frozen core is trusted for that member.** The one undetectable failure — a non-forcing channel that *newly* reads an axis field — is exactly what Plane 3's declared-edge affected-set **cannot see**, so a member-config change forces re-validation **unconditionally** (it is never affected-set-pruned). A *structural* change (member's aspect set) instead **re-partitions** the class key (§6) — it never re-uses the old core.
2. **Structural divergence invalidates the class key** (re-partition), never injects (§6). A per-host delta that *adds* an option/key is structural, not a value.
3. **Config-dependent quirks are gated, not default** (open decision D5). Enabling **any** config-dependent quirk flips the **fleet-wide all-or-nothing `hasAnyConfigThunk`** (`resolve.nix:393-408`) → `hostConfigs = mapAttrs (full nixosSystem) collectedHosts` (`:468`, a full peer eval each) — **exactly the fleet blow-up this architecture exists to prevent.** Keep cross-host quirks **pipeline-parametric**; treat a source-config emit as an explicit, annotated **cone-expander**. The `{config,...}` arg gives **no field-level info**, so any source-config exploit must **declare** which fields it reads and assert they are class-invariant (else it reads the per-host axis and is unsound under injection). `spawnNode` already passes `hostConfigs=null` (`spawn-node.nix:115`), keeping a relocated shared node config-free = precisely the class-shareable subset.
4. **Affected-set is sound only over DECLARED edges** (`recordedDeps`); the dynamic read-set is not pure-recoverable. Cross-host dependency edges must be **declared** (the `pipe.collect` graph + host-entity reads); a hidden read outside declared edges is silently missed.

## 8. Role split (the end-state stack)

- **den-hoag — the flake entrypoint + the declarative decomposition.** Owns eval; declares the class (aspect-set), the per-host axis (entity record), the open/closed boundary (quirk arg-shape), and cross-host relations (`pipe.collect`/`derive` rules). Structures the eval as archetype-core-then-members.
- **gen — the primitive substrate.** `gen-scope` (shared/relocatable nodes + selective materialization), `gen-graph` (edge-map algebra + point queries + condensation), `gen-rebuild` (override/affected/propagate + provenance + the relocatable store), `gen-derive` (relationship rules).
- **hola — per-node nixpkgs-module hosting + the byte-identical guarantee.** Hosts unmodified nixpkgs modules at each node; the parity gate is the per-class validation oracle and the migration-correctness proof (den-hoag+hola+gen reproduces today's per-host drvPaths byte-for-byte before any sharing is switched on).

### 8a. The den-hoag quirk/attribute-evaluation seam (the D5 deliverable)

den-hoag is **not yet shipped**, so the fleet findings get to *specify* its quirk/attribute-eval seam rather than patch the existing one. Gate A/B ground four design points (S1–S4). **Surface-compatibility (the open question):** the `pipe.from … collect/collectAll` cross-host surface is the **right channel and stays** — Gate A found 11/11 real cross-host emits use it correctly. The seam **adds** `pipe.reads` (S2) and a lint (S2), and **removes one internal** (the global flag, S1); it is backward-compatible for the existing closed emits, not a surface redesign.

- **S1 — kill the global flag; laziness *is* the per-edge scope.** Gate A measured (`/tmp/d5_lazy_probe.nix`) that den's `hostConfigs` is already a **lazy `mapAttrs`** forced only by a config-dependent collect-edge that *matches* a sid — a config-dep collect from axon-02 forces **axon-02 alone**, the other 6 untouched. So per-edge scoping already exists; the only defect is the **global `hasAnyConfigThunk` boolean** (`resolve.nix:393-408`, already `true` on the fleet via two *local* age-secret emits, harmless only because nothing forces the map). The seam replaces it with an **always-lazy per-sid memoized `hostConfigFor sid`** threaded into `resolveEntry`, with `specsByHost`'s key-set restricted to the union of config-dependent collect-edge-matched scopes — killing the latent eager-consumer footgun without changing the (already-correct) cost.
- **S2 — the cone-expander: declare the FIELDS, not just the peer.** An open `{ config, … }` emit annotates the paths it reads — `pipe.reads ["services.k3s.token"]` — and is resolved against a **cone-restricted partial peer config** (`gen-scope subtreeOf` / a restricted `evalModules` over the declared paths) instead of the peer's full `nixosSystem`. Open-emit cost drops from `O(matched-peers × full-config)` to `O(declared-peers × declared-cone)`, reusing the gen-rebuild cone + gen-scope subtree substrate. A **lint rejects unscoped open emits** (`collectAll (_: true)` + config-dep — the only real blow-up shape). This is "DECLARE the boundary not DISCOVER it" extended to the *open* axis at field granularity.
- **S3 — axis/core separation = the closed-injection seam (Gate B-proven).** The class core is evaluated once (axis-free) and **`mkForce`-injected as a plain projection into each member via `extendModules`** at the `host.instantiate` seam (`host.nix:397`). Gate B proved this on real axon: the injection is honored **without recompute** (`filterOverrides` drops the real def unforced, `REAL-DEF-FORCED=0`), the core is forced **once across two distinct member fixpoints** (`CORE-FORCED=1` vs reconstruct `=2`), and the result is **byte-identical** to from-scratch (`a02-core→a03 system.path == a03`, `z81p0vvk…`). The per-host axis (the ~7-field entity record) is the late-bound delta; **class key = sorted `den.aspects.<host>.includes`**; aggregation roots stay per-member (§10).
- **S4 — HOAG declared edges (`recordedDeps`) for queries + affected-set.** Quirks/attributes are `gen-scope` nodes whose reads are **declared edges**, auto-populated by an **aspect→resource edge extractor** (the "declare the boundary" build step). Those declared edges simultaneously: bound distributed queries to O(touched) (Plane 1), make the affected-set sound (Plane 3), give blast-radius fidelity, **and supply the cone for S2** (the declared reads *are* the restricted cone). One declaration mechanism serves all four uses.

### 8b. Worked Tier-2 example: a persist-claim for external backup (the `config.…uid` case)

The canonical Tier-2 quirk — emit each service's persist directory + **resolved ownership** for backup. The emit reads the *config* (not the entity record), so it is an **open** `{ host, config, … }` function (the real emit shape, cf. `k3s.nix:48` which is the *closed* `{ environment, host, … }` form). `host.settings.*` is the entity record (closed); `config.users.users.<svc>.uid` is the resolved value (open, Tier-2).

```nix
# modules/den/quirks/persist-claims.nix — SHIPPED surface (decl)
{ den.quirks.persist-claims.description = "Persist dirs + ownership for external backup"; }

# the emit (in the persist aspect) — OPEN: reads resolved config.  SHIPPED surface.
persist-claims = { host, config, ... }:
  map (svc: {
    path = "/persist/${host.name}/${svc}";        # per-host PATH (the identity axis — cheap)
    uid  = config.users.users.${svc}.uid;          # resolved config VALUE — Tier-2 (int, no drv)
    gid  = config.users.groups.${svc}.gid;
  }) host.settings.backup.services;
```

**Form A — host backs *itself* up (LOCAL). SHIPPED, ~free.** The claim is consumed by the *same* host's backup service. den marks the open emit a config-thunk **deferred-local** (`markConfigThunk`, `class-module.nix:157-168`) → resolved inside that host's own `evalModules`, which runs anyway → **zero extra eval**. This is exactly how den handles age-secrets today.

**Form B — central backup orchestrator collects *all* hosts (CROSS-HOST), naive. SHIPPED but the cost the seam exists to fix; the S2 lint REJECTS it.**
```nix
den.policies.collect-persist-claims =
  pipe.from "persist-claims" [ (pipe.collectAll ({ host, ... }: true)) ];  # unscoped + open ⇒ forces EVERY host's config
```
Cost: O(N hosts × the host's module-merge cone) — Tier-2 *values*, so **no** derivation construction (the 94%), but the full per-host module-merge × N. This is the `collectAll (_: true)` + config-dep shape the S2 lint forbids.

**Form C — central backup, SCOPED + cone-declared (the seam). S2/S4 PROPOSED surface.**
```nix
den.policies.collect-persist-claims =
  pipe.from "persist-claims" [
    (pipe.reads [ "users.users" "users.groups" ])                 # S2: declare the open emit's config cone
    (pipe.collect ({ host, ... }: host.settings.backup.central))   # scoped predicate (NOT collectAll _:true)
  ];
```
Cost: O(collected-hosts × the **uid/gid cone**) — each source host resolved against a config restricted to `users.users`/`users.groups` (gen-scope `subtreeOf` / restricted `evalModules` over S4's declared modules), not its full config. **And class-shared:** axon's uids are deterministic (measured byte-identical across axon-02/03), so the cone resolves **once per class** → O(classes × uid-cone) + O(hosts × cheap path). The O(K) parity gate validates the uid is genuinely class-invariant; a host using non-deterministic allocation diverges and is correctly resolved per-host.

**Takeaway for the API:** Tier-2 is first-class and affordable — `pipe.reads` is the one new verb that turns an open emit from "full peer config × N" (Form B) into "declared cone × classes" (Form C); deferred-local (Form A) already makes the self-backup case free on shipped den.

## 9. Honest perf contract

**NOT** total-O(|AFFECTED|). The win is the **sub-root closure** (the 10986 shared drvs lifted off the N-axis). The per-host residual is irreducible: re-run the cheap **aggregation roots** (`etc`/`system-units`/`activate`/`toplevel`) over shared inputs + the ~43 fresh leaf derivations. **Do not attempt to share the aggregation roots.** `propagateEager` gives a constant-factor expensive-axis win on cut-heavy cones; **Determinate parallel-eval (~3.7×, verbatim nixpkgs, zero code)** composes on top for the residual tail and for the cold full-fleet case. Plane 2's value is removing the N-multiplier from the dominant cost; Determinate's is parallelizing what remains.

## 10. Staging

The gates ran (workflow `wh0ygg53t`) and **all three passed** — the existential premise was put on the critical path before any build.

**Gates (DONE):**
- ✅ **Gate A — D5 boundary: gate-pass-constrained.** 11/11 real cross-host emits pipeline-parametric (100% closed); the only 2 config-dep emits are *local* age-secrets. Per-edge scoping is already inherent via Nix laziness (`/tmp/d5_lazy_probe.nix`: a config-dep collect from axon-02 forces axon-02 alone, the other 6 untouched). The seam fix is §8a S1 (kill the latent global flag) + S2 (cone-expander) — refinements, not a blocker. *Constraint:* open cross-host emits must use scoped predicates (the S2 lint).
- ✅ **Gate B — Plane 2a real-axon: 2a-real-win.** Eval-**work** shared (`CORE-FORCED=1` vs reconstruct `=2`), byte-identical, on real axon-02/03 (§8a S3 / §5). Answers the drvPath≠work-shared caveat on the real seam.
- ✅ **Plane 1 — works at zero force**, ship-ready against the entity-record extract.

**Build order — centered on the open emit (§0); closed Tier-1 is the baseline, not a step.**
1. **Unlock the open emit on real axon (the capability demo).** Wire one real **open** cross-host quirk — the central persist-claim collector reading `config.users.users.<svc>.uid` (§8b Form C) — with a **scoped** `pipe.collect` predicate. Per Gate A this is *already affordable today* (Nix laziness forces only matched peers); measure it on real axon to prove the dormant capability is usable. This is the first thing that has value den lacks today.
2. **den-hoag seam S2/S1 (§8a) — make the open emit *scale*.** `pipe.reads` cone-expander (open emit reads only its declared cone, not the full peer config) + the unscoped-`collectAll`+config-dep lint + eliminate the global `hasAnyConfigThunk` (→ per-sid lazy `hostConfigFor`). This is what takes the open emit from "matched-peers × full-config" to "declared-cone × peers."
3. **Plane 2a class-sharing (§5, Gate-B GO) — make the open emit's reads shared.** Extend the Gate-B proof to the full class-invariant cone so the config an open emit reads (e.g. the deterministic uid) is resolved **once per class**; class key = sorted `den.aspects.<host>.includes`; aggregation roots per-member; gated per-class on the O(K) byte-identical parity gate (§7.1). *Side benefit:* the same sharing gives the N-fold faster fleet build.
4. **Plane 3 — incremental:** `gen-rebuild override` (data) + `applyEdgeDelta`/re-partition (topology), keyed by class; member-config change forces re-validation (§7.1).
5. **Plane 2b (deferred keystone):** the content-addressed cross-invocation persistence store (gen-rebuild *consuming* the threaded-but-unconsumed gen-scope, `FUTURE_WORK`) — O(touched) provenance/blast-radius *across* invocations + cross-host result sharing. Net-new; 2a does **not** imply 2b.
- *(Tier-1 closed queries already work on shipped den; the two live-flake niceties — a `flake.den.hosts` debug output + the aspect→resource extractor (S4) — help any query but are not the value and not blockers.)*

## 11. Open decisions for the user

- **D1 — class-key lifecycle:** where is `sorted(includes)` computed/stored (den entity registry)? Is `axon-01` a separate super-class or core+`media-scratch` overlay? What enforces re-partition-before-injection when a host's aspect set changes?
- **D2 — the frozen projection:** drvPath vs out-path vs a serializable config slice; query-only vs build-reconstruction projections.
- **D3 — Plane 2b substrate:** the net-new cross-host persistence — does it require a build step? (IFD/recursive-nix are out; a plain-projection CA store is the candidate.)
- **D4 — soundness gate placement + re-validation trigger:** where the O(K) validation lives, what it gates on (declared class-invariant fields), and the trigger — a member-config change must force re-validation **unconditionally** (never affected-set-pruned, since the failure case is a non-forcing channel the declared-edge affected-set can't see; §7.1).
- **D5 — the den-hoag quirk/attribute-eval SEAM: RESOLVED into the design §8a (S1–S4), Gate-A/B grounded.** Remaining choice: the §8a S2 `pipe.reads` annotation **surface** (exact API) and whether to ship S1 (global-flag removal) as a standalone den cleanup ahead of den-hoag. The seam is the highest-leverage place the fleet findings shape den-hoag.
- **D6 — first-cut scope:** axon-only, or general class-partition from day one?

## 12. References

- Grounding: workflow `weqp366dj` (axon config/measurement, den quirk-pipes, gen APIs). Gate validation: workflow `wh0ygg53t` (Plane 1 zero-force engine, Gate A `/tmp/d5_lazy_probe.nix` per-edge laziness, Gate B real-axon `CORE-FORCED=1` work-share). Probes: `/tmp/hola_homogeneous.nix` (2-vs-N class sharing), `/tmp/hola_selective.nix` (0 toplevel-forces / 200-host query), `/tmp/hola_c2_cost.nix`, `/tmp/hola_c1a0_realdiff.nix`, `/tmp/hola_typed_vs_lazy.nix`, `/tmp/hola_presence.nix`.
- Source anchors — den (`~/Documents/repos/den`): `resolve.nix:392` (isConfigDependent), `:393-408` (hasAnyConfigThunk), `:468` (hostConfigs B′ re-entry); `assemble-pipes.nix:32/71/88-105` (boundary/markConfigThunk/peer-config resolve); `spawn-node.nix:115` (hostConfigs=null); `class-module.nix:168` (deferred-local); `policy-effects.nix:296-346` (pipe API); `host.nix:258-283/378-386/391/392/397` (axis carriers + instantiate). nix-config: `axon-0N.nix:48-63`, `axon-01.nix:60`, `clusters/axon.nix:72-120`. gen: `gen-rebuild default.nix:5-12` (scope threaded, unconsumed) + `FUTURE_WORK.md`.
- Negative record: `specs/2026-06-24-hola-e3c-c1-cross-scope-sharing-design.md` (per-host discovered-boundary sharing = net-negative; C1-A0 NO-GO).
- Memory: `project_hola`, `project_den_architecture`, `project_hoag_architecture`, `project_gen_rebuild`, `project_claim_provide_engine`, `project_zen_vic`.
