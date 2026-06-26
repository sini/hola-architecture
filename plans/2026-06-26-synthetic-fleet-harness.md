# Synthetic-scale axon fleet + observability harness — Implementation Plan (step 2.0)

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if
> subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a parametric N≈100-host synthetic axon-class fleet plus an observability harness
that measures — at fleet scale, every crumb, every regime — the levers the later pieces (S1, S2,
Plane 2a) will exploit.

**Architecture:** A den host **factory** (class-spec list → N synthetic host entities, identity
axis synthesized per index) rides the real full-axon aspect set in a synthetic
environment/cluster/hub **skeleton**, in a throwaway nix-config worktree branch. An external
**measurement driver** (eval-cache-off, NIX_SHOW_STATS, poison sentinels, canonicalized-core
drvPath oracle) sweeps N/K/cone/channel/role and writes durable reports to the papers archive.
den is **unchanged** in 2.0 (open emits use shipped `pipe.collect`).

**Tech Stack:** Nix (den module system, `lib.evalModules`), bash + `NIX_SHOW_STATS`, python3
(stats/diff), agenix-rekey, gen-graph/gen-rebuild (provenance projection).

**Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-26-synthetic-fleet-harness-design.md`
(read it — every task references a section). **Governing principle: YAGNI rejected** — every
edge case first-class; a measurement that isn't *trustworthy* is worse than absent.

**Worktree:** `~/Documents/repos/sini/nix-config/.worktrees/persist-claims-open-emit` (branch
`demo/persist-claims-open-emit`, off main, **never merged**). All nix-config paths below are
relative to this worktree. New files must be `git add`-ed before `nix eval` (flakes ignore
untracked files). Commit with `PREK_ALLOW_NO_CONFIG=1` (fresh worktree has no
`.pre-commit-config.yaml`). Eval flags throughout:
`--extra-experimental-features "nix-command flakes pipe-operators" --accept-flake-config`.

**Reference patterns in the repo** (read before coding the matching task):
- Host entity shape: `modules/den/hosts/axon-02.nix` (axis fields) + `:48-64` (includes).
- Emit + consumer: `modules/den/aspects/services/k3s/k3s.nix:48-75` (closed emit + `nixos`
  consumer reading a collected quirk).
- Collect policy: `modules/den/policies/pipes.nix` (`collect-*` = `pipe.collect`/siblings,
  `cluster-collect-*` = `collectAll`; `den.schema.host.includes` is a mergeable list).
- The step-1 open emit (the template to generalize): `modules/den/aspects/services/backup/persist-claims-demo.nix`.
- deterministic-uids registry: `modules/den/aspects/core/users/deterministic-uids.nix:136` (frr 978).
- facter default: `modules/den/schema/host.nix:392`.

---

## PHASE 1 — The fleet (Tasks 0–4): N=100 evaluates, criteria 1a/1b met

### Task 0: Synth host factory + identity axis

**Goal:** A parametric factory that emits N synthetic host entities with per-index identity axis
and a computed class key, gated behind `synthFleet.enable` (default OFF).

**Files:**
- Create: `modules/den/synth/factory.nix`
- Create: `modules/den/synth/options.nix` (the `synthFleet` option tree)
- Test: `modules/den/synth/tests/factory-test.nix` (a `nix eval` assertion module, run via the
  app in Task 5; for now a standalone `nix eval --apply` check in **Verify**)

**Acceptance Criteria:**
- [ ] `synthFleet.enable` defaults `false`; with it `false`, `den.hosts` is unchanged from main
      (real axon-01/02/03 only) — verified by attr-name diff.
- [ ] With `synthFleet = { enable = true; classes = [ … ]; }`, the factory produces
      `den.hosts.x86_64-linux.axon-synth-NNN` for each host across all class specs.
- [ ] Each synth host's **identity axis is distinct and synthesized from its index**: hostname
      `axon-synth-NNN`, `networking.interfaces.eth0.ipv4 = [ "10.<a>.<b>.<c>/16" ]` (from index),
      ipv6, thunderbolt loopback ipv4/ipv6 + nsap (`49.0000.0000.<idx>.00`), two synthetic
      `/dev/disk/by-id/nvme-SYNTH-<idx>-{root,longhorn}` strings, bgp `localAsn` (base + idx,
      capped ≤ 1022 — see spec §3.1 bounds), keepalived VRRP nodeId ≤ 255.
- [ ] `synthFleet.observe.classKey.<host>` = `(sorted includes, channel, system)` (role is an
      include, spec §3.1) is exposed for every synth host.

**Verify:**
```
git add modules/den/synth/
nix eval <flags> --apply 'h: builtins.length (builtins.attrNames h)' \
  '.#nixosConfigurations' 2>/dev/null   # sanity: still evaluates
nix eval <flags> '.#darwinConfigurations' >/dev/null  # unaffected
# factory entities present (enable via a test overlay or a committed test value):
nix eval <flags> --apply 'hs: builtins.attrNames hs' \
  '.#den-debug.synthHosts'   # expect axon-synth-001 … (debug output added in this task)
```
Expected: with enable on, N synth host names; identity attrs distinct across two sample hosts.

**Steps:**
- [ ] **Step 1: Read `axon-02.nix` (entity shape) and `host.nix` schema** to mirror the exact
      axis field paths. Note which fields are `mkOption` (must be supplied) vs defaulted.
- [ ] **Step 2: Write `options.nix`** — declare:
```nix
{ lib, ... }:
{
  options.synthFleet = {
    enable = lib.mkEnableOption "synthetic-scale axon fleet (measurement only)";
    classes = lib.mkOption {
      # one entry per class; role is realised AS an include (server/agent aspects).
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          count = lib.mkOption { type = lib.types.int; };
          channel = lib.mkOption { type = lib.types.str; default = "nixos-unstable"; };
          system = lib.mkOption { type = lib.types.str; default = "x86_64-linux"; };
          includes = lib.mkOption { type = lib.types.listOf lib.types.raw; };
          facterRegime = lib.mkOption { type = lib.types.enum [ "shared" "varied" ]; default = "varied"; };
        };
      });
      default = [ ]; # the realistic-axon default is set in skeleton.nix (Task 3)
    };
  };
}
```
- [ ] **Step 3: Write `factory.nix`** — fold the class-spec list into host entities. Index is a
      global running counter across classes (so hostnames/IPs are unique fleet-wide). Pure string
      synthesis from index; NO facter/secrets yet (those are Tasks 1–2). Expose a
      `flake.den-debug.synthHosts` + `synthFleet.observe.classKey` for verification. Reference the
      `genList`/`concatMap` pattern; guard everything behind `config.synthFleet.enable`.
- [ ] **Step 4: Verify + commit** (run Verify; `git add modules/den/synth/`;
      `PREK_ALLOW_NO_CONFIG=1 git commit -m "synth: host factory + identity axis (Task 0)"`).

**Notes / risk:**
- At this task the synth hosts have only a MINIMAL include set (enough to eval the entity, not the
  full nixosSystem). Full-axon includes + no-throw config eval come in Tasks 3a/3b.
- **`enable` wiring (review-Issue-3, pin it now):** the measurement scripts eval
  `.#nixosConfigurations.axon-synth-NNN`, which only exist when synth hosts reach
  `nixosConfigurations`. Because the branch is **throwaway/never-merged**, the chosen mechanism is:
  **commit `synthFleet.enable = true` + the default `classes` on the worktree branch** (a single
  committed `modules/den/synth/_enable.nix`), so every script has a stable target. The
  "default-OFF / real fleet unchanged" guarantee is the **module default** in `options.nix`,
  verified by AC-1's off-diff (eval with the enable file removed). Do NOT rely on per-run overlays.

---

### Task 1: Facter generator (shared / varied regimes)

**Goal:** Attach synthetic facter facts to each synth host, in two regimes, with the ssh host key
derived as a **valid age recipient**.

**Files:**
- Create: `modules/den/synth/facter.nix`
- Create: `modules/den/synth/facter-base.json` (one committed synthetic hardware profile)
- Create: `synth-measure/gen-keys.sh` (one-shot key generator)
- Create: `modules/den/synth/keys/synth-keys.json` (committed pubkeys + age recipients)
- Test: extend `factory-test.nix`

**Acceptance Criteria:**
- [ ] Every synth host has `facts` pointing at a generated facter profile (overriding the
      `host.nix:392` default path) so config eval does not require a per-host file on disk.
- [ ] `shared` regime → all hosts' facter-derived facts byte-identical (the invariance ceiling).
- [ ] `varied` regime → per-host **drift** (disk serial, MAC, cpu count, ssh host key) synthesized
      from index; the ssh host key is a real `ssh-ed25519` public key whose **age recipient**
      (`age1…` via ssh-to-age) is valid (asserted by a parse check).
- [ ] No source-taint is attempted in Nix (spec residual-2); the facter *bucket* is recovered only
      by the two-regime differential in Task 8.

**Verify:**
```
nix eval <flags> --apply 'r: r' '.#den-debug.synthFacter.axon-synth-001.facterRecipient'
# expect a valid age1... string; differs across hosts in varied, identical in shared
```

**Steps:**
- [ ] **Step 1: Determine how facter facts enter config** — grep the nixos-facter / `facts` module
      in the pinned nixpkgs/den (is `facts` `importJSON`-ed at eval? does an absent file throw?).
      This decides whether `facts` must be a path or can be an inline attrset. **Discover
      empirically; record the finding in a comment.**
- [ ] **Step 2: Pin the key generator (review-Issue-7)** — write `synth-measure/gen-keys.sh`:
      loop `i` in `1..MAX`, `ssh-keygen -t ed25519 -N "" -f /tmp/k$i`, `ssh-to-age < /tmp/k$i.pub`,
      and emit a **committed** `modules/den/synth/keys/synth-keys.json` =
      `{ "<idx>": { sshPub, ageRecipient } }`. Only the PUBLIC keys + age **recipients** are needed
      (eval-only — these hosts are never deployed, so no private keys at runtime, no IFD). Run it
      once, commit the JSON.
- [ ] **Step 3: Build the facter generator** — a function `mkFacter { idx, regime }` producing the
      facts (start from `facter-base.json`, overlay per-index drift in `varied`: disk serial, MAC,
      cpu count, and the ssh host key read from `synth-keys.json[idx]`). `shared` regime uses
      index 0's values for all.
- [ ] **Step 4: Wire `facts` override per host** in `factory.nix` (via the host entity's facter
      field). Assert the recipient parses (`age1` prefix + length).
- [ ] **Step 5: Verify + commit.**

**Notes / risk (spec §5, residual-3):**
- If an absent `facts` file throws at eval, the generator MUST supply an inline/committed profile.
  Do NOT disable the facter machinery — that would change behaviour. ssh keys must yield valid age
  recipients or Task 2 rekey throws.
- **device_id × facter-disk coherence (review-Issue-6, pre-empt it):** Task 0 synthesizes per-host
  `/dev/disk/by-id/nvme-SYNTH-<idx>-…` entity `device_id`s; this task commits ONE `facter-base.json`.
  Ensure the two don't collide at 1a: either make `facter-base.json` disks **consistent** with the
  entity `device_id` synthesis, or confirm disko keys off the entity `device_id` and facter disks
  are **not asserted** against it. Check whether disko/facter cross-reference disk serials BEFORE
  Task 3b's no-throw sweep (else it surfaces there blind). Record the finding.

---

### Task 2: Synthetic secrets (agenix master + rekey generation)

**Goal:** Make secret-bearing aspects eval without removing them — a synthetic agenix master and a
rekey **generation** step producing the N hosts' secret store paths.

**Files:**
- Create: `modules/den/synth/secrets.nix`
- Create: `modules/den/synth/keys/synth-master.{age,pub}` (committed synthetic master)
- Create: `synth-measure/00-rekey.sh` (the generation step)
- Test: a no-throw eval of a synth host's `config.age.secrets` attr names

**Acceptance Criteria:**
- [ ] Each synth host's agenix recipient = its facter-derived age pubkey (Task 1); the synthetic
      master is the rekey identity.
- [ ] `synth-measure/00-rekey.sh` runs agenix-rekey for the synth fleet and produces the rekeyed
      store paths so `config.age.secrets.<n>.file` resolves; documented as a **generation step**,
      not config-only.
- [ ] A synth host's config fixpoint reaches `config.age.secrets` (names) **without throwing**.
- [ ] **No aspect-disable fallback** is used for any cone-bearing/class-defining aspect (spec §3.1,
      residual-3); if rekey can't resolve, fix the master/recipient wiring, do not drop the aspect.

**Verify:**
```
bash synth-measure/00-rekey.sh           # generation
nix eval <flags> --apply 'builtins.attrNames' \
  '.#nixosConfigurations.axon-synth-001.config.age.secrets' 2>&1 | head
# expect secret names, no throw
```

**Steps:**
- [ ] **Step 1: Read the agenix battery** (`modules/den/batteries/agenix.nix`,
      `modules/den/aspects/secrets/agenix.nix`) — how recipients + master identity are configured;
      whether rekey is eval-time or a CLI/build step. **Record the finding.**
- [ ] **Step 2: Generate a synthetic master keypair** (committed; test-only — clearly labelled).
      Point the synth fleet's rekey recipients at the per-host facter age pubkeys.
- [ ] **Step 3: Write `00-rekey.sh`** invoking the repo's agenix-rekey entrypoint scoped to synth
      hosts. Confirm the produced paths satisfy `config.age.secrets.<n>.file`.
- [ ] **Step 4: Verify + commit.**

**Notes / risk:** this is the spec's highest-uncertainty task. If agenix-rekey can't be scoped to
synth hosts cleanly, fall back to a **fixed shared dummy secret set** (one rekeyed value reused as
every secret's source) — still NO aspect removal. Document whichever path is taken.

---

### Task 3a: Full-axon class assembly + topology skeleton (structure)

**Goal:** Give synth hosts the **full axon class** in a coherent synthetic
environment/cluster/hub. STRUCTURE only — entities + includes resolve; the no-throw-at-scale proof
is Task 3b.

**Files:**
- Create: `modules/den/synth/skeleton.nix` (synth environment + cluster + bgp hub; the
  realistic-axon default `classes`, incl. server/agent realized as **distinct includes**)
- Modify: `modules/den/synth/factory.nix` (apply each class's `includes` to its hosts)

**Acceptance Criteria:**
- [ ] Default `synthFleet.classes` = a realistic-axon mix: a base class (the axon-02/03 include
      set + the step-1 open emit), a superclass (+`services.storage.media-scratch`), a **server vs
      agent** split realized as **distinct k3s aspect includes → distinct class keys**, spread
      across **≥2 channels**. A realistic k3s shape = few servers + many agents.
- [ ] A synth environment + cluster + one synthetic **bgp hub** host exist so spoke/k3s/mesh
      resolve; the hub auto-discovers the synth spokes.
- [ ] `synthFleet.heavyClosedAspects` toggle exists (gates k3s node-collect / mesh O(N²)); **a
      sweep dimension, not a fixed default** (review-Issue-4) — Task 6/11 vary it.
- [ ] Each host's `config` attrset is **reachable** (`nix eval` of a shallow `config` attr name
      list does not throw) at N=10 — full forcing is 3b.

**Verify:**
```
nix eval <flags> --apply 'c: builtins.head (builtins.attrNames c.systemd.services)' \
  '.#nixosConfigurations.axon-synth-001.config' 2>&1 | tail   # structure resolves, no throw
```

**Steps:**
- [ ] **Step 1: Assemble the default `classes`** mirroring `axon-0N.nix:48-64`; add the server vs
      agent k3s aspect split (find/define the agent aspect), the superclass delta, ≥2 `channel`s.
- [ ] **Step 2: Build the skeleton** — synth environment + cluster entities + a bgp hub host
      (mirror `bgp.nix:358`). Ensure `pipe.collect` siblings resolve to the synth environment.
- [ ] **Step 3: Verify structure (N=10) + commit.**

**Notes:** VRRP nodeId ≤255 / unique loopbacks+nsap/localAsn≤1022 (Task 0 synthesis guarantees
uniqueness — assert it here).

---

### Task 3b: Criterion 1a — config fixpoint forces without throwing at scale

**Goal:** Prove every synth host's config fixpoint forces without throwing, N=10→50→100. **This is
the eval-feasibility / debug task — where all §5 landmines (secrets coherence, bgp-hub-at-100,
k3s-cluster, mesh, device_id×facter) surface.** Isolated so the debugging is its own checkpoint.

**Files:**
- Create: `synth-measure/1a-nothrow.sh` (the force-depth no-throw check)

**Acceptance Criteria:**
- [ ] **Criterion 1a:** for N=10 then N=50 then N=100, every synth host's config fixpoint forces
      **without throwing**, where "force" = `deepSeq` of `config.assertions` + the in-cone subtrees
      `{systemd, networking, disko, age}` **minus derivation-building leaves** (spec §4.1a). A throw
      surfaces the host + the option path.
- [ ] **Coverage ceiling stated** (spec §4.1a): a throw outside `{assertions,systemd,networking,
      disko,age}` and unreferenced by any assertion is out of the net — a 1a green = "throw-free in
      the forced cone," not whole-config-proven. The script prints this caveat.
- [ ] At N=100, run **once with `heavyClosedAspects` off** (fast, proves host-local coherence) and
      **once on** (proves the closed-aggregation evals) — sequence so 1a is reachable even if the
      O(N²) on-path is slow.

**Verify:**
```
SYNTH_N=10 bash synth-measure/1a-nothrow.sh    # then 50, then 100 (off then on)
# expect: "1a PASS: <N> hosts, 0 throws (cone={assertions,systemd,networking,disko,age})"
```

**Steps:**
- [ ] **Step 1: Write `1a-nothrow.sh`** — per host, `nix eval --option eval-cache false` an
      `--apply` that `deepSeq`s `config.assertions` + the in-cone subtrees and returns `true`;
      aggregate; on throw print host + path.
- [ ] **Step 2: Iterate to green** — debug the SPECIFIC throw (`feedback_debug_before_revert`);
      never drop a cone-bearing/class-defining aspect (corrupts the partition). Expected landmines:
      Task-2 secrets coherence, the device_id×facter disk split (Task 1 note), bgp-hub at 100
      spokes, k3s server-cluster validity, 100-peer mesh.
- [ ] **Step 3: Verify (N=10,50,100; heavy off then on) + commit.**

---

### Task 4: Open-emit variants + collect modes + S1 trigger + cycle test (criterion 1b)

**Goal:** Generalize the step-1 open emit into the full set of measurement fixtures and prove they
resolve at N=100.

**Files:**
- Create: `modules/den/synth/open-emits.nix` (light/heavy/host-varying/empty cones; the
  `collectAll` global-flag trigger; the mutual-collect cycle fixture)
- Create: `modules/den/synth/collect-policies.nix` (central-O(N) and per-host-O(N²) modes)
- Test: `synth-measure/1b-resolve.sh`

**Acceptance Criteria:**
- [ ] Four open-emit fixtures: **light** (`config.users.users.frr.uid` — step-1), **heavy**
      (reads a `systemd.services`-class structure), **host-varying** (result depends on reader
      ip/asn/loopback → non-shareable), **empty-cone** (matches zero peers).
- [ ] Collect mode is a named toggle (spec §3.2): `central` = consumer on ONE collector host;
      `perHost` = consumer via `den.schema.host.includes`. **per-host mode reads only CLOSED peer
      data in the reciprocal direction** (acyclic fan-out) so the O(N²)-open curve is measurable.
- [ ] A **global-flag trigger** fixture (a scope-ambiguous `collectAll` config-dep emit, behind a
      knob, default off) that trips `resolve.nix:393-408` — so S1 (Task in 2.1) has something to
      bite on.
- [ ] A **mutual-collect cycle** fixture (symmetric value-dependency) is the **rejection test**:
      it must be correctly rejected / detected, NOT hang (bounded by `timeout`).
- [ ] **Criterion 1b:** every (non-cycle) open emit resolves at N=100; the host-varying emit yields
      per-reader-distinct values; empty-cone yields `[]`.

**Verify:**
```
SYNTH_N=100 bash synth-measure/1b-resolve.sh
# expect: light/heavy/host-varying/empty all resolve; cycle fixture → "rejected" within timeout
```

**Steps:**
- [ ] **Step 1: Generalize `persist-claims-demo.nix`** into the four cone fixtures (distinct quirk
      names) + their collect policies; host-varying reads `config.networking…`/the reader's axis.
- [ ] **Step 2: Implement the collect-mode toggle** (central vs per-host wiring of the consumer).
- [ ] **Step 3: Add the global-flag trigger + the cycle fixture** (both knob-gated, default off).
- [ ] **Step 4: Write `1b-resolve.sh`** (resolve each fixture; `timeout` the cycle).
- [ ] **Step 5: Verify (N=100) + commit.** ← **PHASE 1 checkpoint: fleet evaluates, 1a+1b met.**

---

## PHASE 2 — The observability layer (Tasks 5–11)

### Task 5: Measurement driver core (eval-cache-off + stats + variance)

**Goal:** The shared measurement primitives every later tool uses.

**Files:**
- Create: `synth-measure/lib.sh` (eval wrapper: forces `--option eval-cache false` + a cache-bust
  arg; `NIX_SHOW_STATS` capture; emits a JSON row)
- Create: `synth-measure/lib_stats.py` (median/IQR over repetitions; deterministic vs noisy split)
- Test: `synth-measure/tests/lib-test.sh`

**Acceptance Criteria:**
- [ ] Every measured eval runs `--option eval-cache false` + varies an arg (a cache-bust), proven
      by a re-run reporting non-zero `nrFunctionCalls` (a cached run reports ~0).
- [ ] `nrFunctionCalls`/`nrOpUpdateValuesCopied` are reported as **load-bearing deterministic**
      counters; `cpuTime`/`maxRSS` get **N repetitions + median/IQR** (spec §3.3, residual-15).
- [ ] Output is a stable JSON schema consumed by Tasks 6–11.

**Verify:** `bash synth-measure/tests/lib-test.sh` → "cache-off enforced; fn deterministic across
runs; cpuTime median/IQR computed".

**Steps:** wrapper + python; assert determinism of fn/copies across 3 repeats; assert cache-off via
the non-zero re-run. Commit.

---

### Task 6: Differential per-edge / per-peer perf

**Goal:** Attribute per-peer open-emit cost via differentials (one global stat can't, spec §3.3).

**Files:** Create `synth-measure/perf-differential.sh`; Test `synth-measure/tests/perf-test.sh`.

**Acceptance Criteria:**
- [ ] Per-peer increment = `stats(collect over N+1 peers) − stats(collect over N)`, **within a
      fixed class** (per-class marginal — the grown class is named).
- [ ] force-one vs force-none differential isolates a single edge's cost.
- [ ] Scaling rows emitted vs **N, K, cone-weight, channel-count, role-mix, and
      `heavyClosedAspects` on/off** — the last so the **closed-aspect O(N²) and open-emit O(N²) are
      reported as SEPARATE curves** (review-Issue-4): open-emit cost = `stats(open collect, heavy
      off)`, closed-aspect cost = `stats(heavy on) − stats(heavy off)`, so k3s-cert/mesh O(N²) can't
      silently pollute the open-emit reading.

**Verify:** `bash synth-measure/perf-differential.sh --sweep N` → monotone per-peer increment;
heavy-cone increment > light-cone (the spec §1 8.32M vs 2.68M shape, at scale).

**Steps:** implement the N vs N+1 (fixed-class) and force-one/force-none diffs over `lib.sh`;
emit curves. Commit.

---

### Task 7: Multi-depth poison sentinels (force-counter)

**Goal:** Count which peers a collect forces, at value- AND structure-depth.

**Files:** Create `modules/den/synth/sentinels.nix` (value-poison + structure-poison overlays);
Create `synth-measure/force-count.sh`; Test `synth-measure/tests/sentinel-test.sh`.

**Acceptance Criteria:**
- [ ] **value-poison**: a peer's read value `throw`s → a clean eval proves that peer's *value* was
      not forced. **structure-poison**: the peer's `attrNames`/key-presence `throw`s → detects
      structure forcing a value-poison misses.
- [ ] Reported quantity = **value-forcing under the throws-OBSERVED ceiling**; structure-forcing
      reported separately (not conflated). A `tryEval`-wrapped force is invisible to BOTH —
      asserted and documented (spec §3.3, residual-3 + nit).
- [ ] Per-edge force-set + force-set-size; scoped `collect` force-set ≈ matched (not N).

**Verify:** `bash synth-measure/force-count.sh` → scoped collect forces ≈ matched siblings; a
planted structure-only reader is caught by structure-poison but NOT value-poison (proving the two
depths differ).

**Steps:** build the two sentinel overlays (override a target peer's emit to `throw` at value vs
structure depth); the bash harness flips the poison per target and records clean/throw. Commit.

---

### Task 8a: Class partition + exact/near-class share ratios

**Goal:** Partition the fleet and report the two structural share ratios.

**Files:** Create `synth-measure/partition.py`; Create `synth-measure/share-ratio.sh`; Test
`synth-measure/tests/partition-test.sh`.

**Acceptance Criteria:**
- [ ] Partition by class key `(sorted includes, channel, system)` (role-as-include → server/agent
      are distinct classes); report K, class sizes, with a **singleton** class present in the sweep.
- [ ] **exact-bucket** share ratio AND **near-class** share ratio, side by side, near-class rule
      stated: same-`(channel,system)` ONLY, `base` = maximal common include-set of the group,
      membership `includes ⊇ base ∧ |delta| ≤ threshold` (threshold a reported knob); cross-channel
      /cross-system pairs NEVER grouped.

**Verify:** `bash synth-measure/tests/partition-test.sh` → server and agent land in DIFFERENT
classes; a singleton class is present; near-class groups never cross channel/system.

**Steps:** read `observe.classKey` per host; group; compute exact + near-class membership by the
stated rule; emit. Commit.

---

### Task 8b: Two-regime facter differential (core / identity / facter split)

**Goal:** The Plane-2a content split — recover the core/identity/facter buckets WITHOUT pure-Nix
source-taint, soundly (this is the review's most-severe fix; a naive method reports fake-high
sharing).

**Files:** Create `synth-measure/regime-diff.sh` + `synth-measure/regime_diff.py`; Test
`synth-measure/tests/regime-diff-test.sh`.

**Acceptance Criteria:**
- [ ] **VALUE-level cross-HOST diff-of-diffs (review-Issue-1 — NOT option-name set-difference):**
      facter/identity drift lives in option *values*, not in which option *names* exist (every host
      defines the same names). So per class, within each regime, compute the set of in-cone option
      **PATHS whose VALUES differ between two same-class hosts**:
      - `idPaths = cross-host value-diff in shared-facter` (only identity varies) = identity bucket.
      - `idFacterPaths = cross-host value-diff in varied-facter` (identity ∪ facter vary).
      - **`facterPaths = idFacterPaths − idPaths`**; `core = allInConePaths − idFacterPaths`.
- [ ] **Comparison surface pinned (no whole-config `toJSON` — functions/derivations don't
      serialize, memory caveat):** compare **per-aspect sub-derivation drvPaths** and/or **hashed
      leaf values** over the same in-cone subtrees Task 3b deepSeqs (`builtins.hashString` of a
      `deepSeq`-forced leaf, or `.drvPath` of each `systemd.services.<x>` / `environment.etc.<x>`),
      pairwise between two same-class hosts.
- [ ] Reports BOTH regimes: `shared-facter core` (the invariance **ceiling**) and `varied-facter
      core` (the realistic number); **varied core < shared core** (the §1/#1 point — a shared
      profile over-credits the core). The **joint-function assumption** (no in-cone path is a joint
      function of BOTH identity and facter) is printed with the number.

**Verify:** `bash synth-measure/regime-diff.sh` → a non-empty `facterPaths` bucket in `varied`
(disk/mac/ssh-host-key-derived paths) and an empty/degenerate one in `shared`; `varied core <
shared core` strictly.

**Steps:**
- [ ] **Step 1:** build the leaf-hashing eval (`--apply` over the in-cone subtrees → per-path
      hash/drvPath, per host), eval-cache off.
- [ ] **Step 2:** for a same-class host PAIR, value-diff in each regime → `idPaths`,
      `idFacterPaths`; subtract → `facterPaths`, `core`.
- [ ] **Step 3:** assert `varied core < shared core`; print the joint-function assumption; emit
      both numbers. Commit.

**Notes / risk:** the pair-based diff assumes the two sampled same-class hosts differ ONLY by
axis/facter (true by construction — same class key). If a class has >2 members, use the union of
pairwise value-diffs to avoid missing a path that happens to agree on one pair.

---

### Task 9: Canonicalized-core parity oracle

**Goal:** The 2a soundness oracle — same-class hosts share output once identity+facter are
neutralized; and it has teeth.

**Files:** Create `synth-measure/parity-oracle.sh` + `modules/den/synth/canonicalize.nix` (the
identity+facter sentinel override); Test the planted-leak negative.

**Acceptance Criteria:**
- [ ] For each class, take a **comparison PAIR** of distinct same-class hosts, override their
      identity+facter axis attrs to a fixed sentinel, and assert `toplevel.drvPath` **equality** of
      the canonicalized configs (spec §3.3, residual-1). Budget ≈ 2 toplevel forces per class (≪ N).
- [ ] **Override surface = the Task-0 identity-axis enumeration ∪ facter, VERBATIM
      (review-Issue-5):** `canonicalize.nix` must override EXACTLY: `hostname`, `ipv4`, `ipv6`,
      thunderbolt loopback `ipv4`/`ipv6`, `nsap`, both disk `device_id` strings, bgp `localAsn`,
      VRRP nodeId, and `facts` (the facter axis). MISSING a field → clean same-class hosts diverge →
      false FAIL; OVER-covering (sentinelizing a non-axis field) → masks a real leak → false PASS
      (defeats the teeth). An AC-level check asserts the override key-set == the Task-0 axis key-set.
- [ ] **Teeth (negative test):** a planted per-host value placed OUTSIDE the declared axis (e.g. an
      extra `environment.etc` keyed by index) makes the canonicalized drvPaths **diverge** → oracle
      reports FAIL. Removing the leak → PASS. (Proves the oracle isn't constant-true.)
- [ ] Raw (non-canonicalized) cross-host drvPath is shown to be constant-UNequal (why the
      canonicalization is needed).

**Verify:** `bash synth-measure/parity-oracle.sh` → PASS per class on the clean fleet; flip the
planted-leak knob → FAIL (teeth proven).

**Steps:** the canonicalize overlay (override entity identity+facter to sentinels); the bash
oracle (pair per class, drvPath compare); the planted-leak knob + negative assertion. Commit.

---

### Task 10: gen-rebuild provenance projection

**Goal:** Project the emit/collect dependency graph so `why`/`support`/`dependentsFrontier` answer
distributed-query/blast-radius — or document the slip to 2.4.

**Files:** Create `modules/den/synth/provenance.nix`; Test `synth-measure/tests/provenance-test.sh`.

**Acceptance Criteria:**
- [ ] Project a gen-rebuild graph: **nodes = emits + collects**, **edges = collect-depends-on-emit**
      (spec §3.3). Source the edges from the fleet's pipe wiring.
- [ ] `why(collect)` / `support(value)` return the contributing emits; `dependentsFrontier(host)` =
      the blast-radius (which collects re-eval if host X's emit changes), bounded at plane edges.
- [ ] **Slip hatch:** if the projection proves heavy/ill-defined, this task delivers instead a
      written decision + a minimal stub deferring provenance to the 2.4 observability layer (spec
      §3.3 explicitly permits this) — NOT a silent omission.

**Verify:** `bash synth-measure/tests/provenance-test.sh` → `why` returns the expected emit set for
a sample collect; OR the documented deferral with rationale.

**Steps:** read gen-graph/gen-rebuild APIs (`why`/`support`/`dependentsFrontier`); build the edge
projection from the pipe policies; test on the synth fleet. If blocked, write the deferral. Commit.

---

### Task 11: Baseline N=100 measurement + durable reports

**Goal:** Run the full sweep and capture the substrate's reference numbers durably.

**Files:** Create `synth-measure/baseline.sh` (orchestrates Tasks 6–9 across the sweep); Create the
report + raw stats under papers `analysis/experiments/synthetic-fleet/`.

**Acceptance Criteria:**
- [ ] Sweep N∈{10,50,100}, K (≥3 via class distribution), cone∈{light,heavy,host-varying,empty},
      channel∈{≥2}, role∈{server,agent}, **`heavyClosedAspects`∈{off,on}**; eval-cache off throughout.
- [ ] A markdown report under papers `analysis/experiments/synthetic-fleet/README.md` with: the
      N/K/cone/channel/role scaling curves (deterministic fn/copies; cpuTime median/IQR), the
      **closed-aspect vs open-emit O(N²) curves SEPARATELY** (review-Issue-4), the **S2 cone-savings
      ratio** (heavy-cone cost vs light-cone cost vs the full-config/toplevel cost — the §3.3 Cone
      sub-crumb, computed from Task 6 + Task 9), **both** facter-regime share ratios (shared ceiling
      + varied realistic), **both** exact and near-class ratios, the parity-oracle result per class,
      force-counts, and the provenance result-or-slip.
- [ ] The throwaway branch patch + raw stats JSON committed alongside (as in step-1 evidence).
- [ ] **Every honest caveat carried into the report** (throws-OBSERVED ceiling, 1a force-depth
      coverage ceiling, joint-function assumption, drvPath≠eval-shared).

**Verify:** `bash synth-measure/baseline.sh && ls analysis/experiments/synthetic-fleet/` → report +
stats present; numbers populated; caveats section present.

**Steps:** orchestrate the sweep; render the report; capture the patch + stats to papers; commit
papers (separately from the worktree). ← **2.0 COMPLETE: substrate built + baseline measured.**

---

## Dependencies

Full task list: **0, 1, 2, 3a, 3b, 4** (Phase 1) → **5, 6, 7, 8a, 8b, 9, 10, 11** (Phase 2).

- **Phase 1 is a chain:** 0 → 1 → 2 → 3a → 3b → 4 (each needs the prior to eval). **Checkpoint
  after Task 4:** fleet evaluates at N=100, criteria 1a + 1b met.
- **Phase 2 all depends on the Phase-1 checkpoint** (the fleet must eval before anything measures
  it). Within Phase 2: **Task 5 (driver core) first**, then 6 / 7 / 8a / 8b / 9 build on it; **8b
  needs both facter regimes** (Task 1); **Task 7 (sentinels) couples to Task 4** — its poison
  overlays target the peers a Task-4 collect reads, so 7's fixtures reference 4's collect modes;
  **Task 10 (provenance) is independent-ish** (can slip to 2.4 per its AC); **Task 11 needs 6–10**.
- The single Phase-1 → Phase-2 ordering is the only hard barrier; 6/7/8a/8b/9 can be done in any
  order after 5.

## Cross-cutting reminders
- New nix files: `git add` before `nix eval`. Commit with `PREK_ALLOW_NO_CONFIG=1` (fresh worktree).
- Every measured eval: `--option eval-cache false` + cache-bust. **Phase-1 scripts (`1a`/`1b`)
  hand-roll this before Task 5's `lib.sh` exists; Phase 2 must refactor them onto `lib.sh`** so
  cache-off enforcement lives in ONE place (DRY).
- Debug the specific throw before changing approach (`feedback_debug_before_revert`); **never drop a
  cone-bearing/class-defining aspect** (corrupts the partition).
- Worktree branch is throwaway; durable artifacts = the papers report + patch + stats.
- den is UNCHANGED in 2.0 (open emits use shipped `pipe.collect`).
