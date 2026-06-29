# Plane-2a class-core eval-sharing PoC Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the synthetic-fleet harness's measured **0.96 content-shareability ceiling** into an **actual, measured, intra-process eval-work saving** — the first hard number for the fleet-eval-sharing arm — by assembling N same-class hosts' `systemd.units` two ways in one eval (vanilla = N independent full unit maps; 2a = one shared class-core archetype + per-host axis-delta) and reporting the copies differential, gated byte-identical by the existing parity oracle so the sharing is sound-by-construction.

**Architecture:** Each synth host is a separate `lib.nixosSystem` ⇒ a separate `evalModules` fixpoint ⇒ separate thunks for the resolved config, even when same-class hosts' rendered unit drvPaths are byte-identical (224/225). So Nix's automatic memo shares only the ~25% nixpkgs/stdenv base; it re-pays the ~75%-of-base per-host marginal (≈21.7M copies measured) for byte-identical class-core derivations. The PoC models "archetype-once + axis-injection" at the units level: pick the largest same-class set; discover the axis-dependent unit key-set Δ by a one-time two-host drvPath diff; build `archUnits` = host0's shared-core units (forced **once**); assemble each other host as `archUnits // (recompute only its Δ units)`. Measuring copies of `deepSeq vanilla` vs `deepSeq 2a` across N isolates the **shared deep-derivation construction** lifted off the N-axis. **Harness-only — no den change**; production wiring of this saving is the den-hoag "inject at `host.instantiate`" seam (architecture spec §8a, deferred). Cross-invocation persistence (the dev-loop-free story) is Plane 2b (gen-rebuild content-addressed, deferred).

**Tech Stack:** the synthetic-fleet harness on the nix-config worktree `~/Documents/repos/sini/nix-config/.worktrees/persist-claims-open-emit` (`modules/den/synth/**` + `synth-measure/**`); `synth-measure/lib.sh` eval contract (NIX_SHOW_STATS `nrOpUpdateValuesCopied` = deterministic copies, eval-cache off, per-rep cache-bust, `--apply` over `.#nixosConfigurations`); the parity substrate `parity-oracle.sh` + `modules/den/synth/canonicalize.nix` (soundness gate) + `partition.py` (class partition).

---

## Context the implementer needs (read before Task 0)

**The measured problem (PoC spec `specs/2026-06-28-plane-2a-class-share-poc.md`, the authoritative design):**

| host set (ONE eval) | copies | marginal |
|---|---|---|
| base: axon-synth-001 | 28.96M | — |
| + 002 (SAME class) | 50.69M | +21.73M = 75.0% of base |
| + 007 (DIFFERENT class) | 50.68M | +21.72M = 75.0% of base |

Same-class marginal == different-class marginal ⇒ Nix shares nothing class-specific; yet the parity oracle proves a same-class host's core is byte-identical (224/225 units drvPath-equal). The 2a upside = the class-invariant fraction of that 75%-per-host marginal.

**The surfaces + primitives (all exist):**
- **Units surface:** `ncs.<host>.config.systemd.units` is a lazy attrset; each unit `u` exposes `u.unit.drvPath` (see `parity-oracle.sh:29` `mapAttrs (n: u: u.unit.drvPath or null)`). Reading one key forces only that unit's derivation (+ its transitive deps), not the whole map.
- **Eval contract** (`lib.sh`): `synth_eval_expr "<apply>"` and `synth_eval_attr <attr>` eval `.#nixosConfigurations` / a flake attr with the limits (`--option eval-cache false`, `--option max-call-depth 1000000`, `ulimit -s unlimited`). The `--apply` function receives the `nixosConfigurations` attrset — call it `ncs`. `synth_measure_reps "<apply>" <reps>` → JSON array of per-rep `{fn,copies,thunks,cpuTime,maxRSSkb}` with a per-rep cache-bust. `lib_stats.py` does determinism + median/IQR.
- **Scale knob** (`lib.sh`): `synth_set_scale n heavy oneB collect gt cyc …` writes `scale.json` (tracked → visible to `nix eval .#`, no `--impure`); `synth_scale_field canonicalize true` / `plantLeak true` toggle the parity-oracle module; `synth_reset_scale` clears. Always `git add scale.json` (lib.sh does this) so the flake sees the dirty content.
- **Class partition** (`share-ratio.sh` + `partition.py`): evals `.#den-debug.classKey` (host → sorted includes/channel/system) → the same-class groups. At N=100 the largest class is ~96 hosts (the 0.96 exact-share ratio).
- **Parity oracle** (`parity-oracle.sh` + `canonicalize.nix`): fingerprints the units drvPath map raw (≠) / canonicalized (=) / canon+leak (≠). `canonicalize=true` sentinelizes EXACTLY the Task-0 identity axis (13 keys: eth0 v4/v6, bgp asn ×2, tb-mesh loopback v4/v6 + nsap, 2 disk device_ids, facts, public_key, secretPath, hostName) ⇒ same-class hosts collapse byte-identical. The **documented residual** `nftables.service` (an out-of-axis firewall leak, not yet traced) is excluded from the fingerprint. The **planted leak** (`plantLeak=true` → `systemd.services.synth-leak`) is the teeth-test: an out-of-axis divergence the gate MUST catch.

**The honest measurement design (do NOT deviate — this is what keeps the number real):**
- **`sharedKeys` = unit keys present on EVERY sampled member AND drvPath-identical across all** (NOT a single pairwise diff — `varied` facter makes one pair under-discover; Task-0 measured 004/005 agreeing where 006 diverged). `deltaKeys` = the rest. Discover over the whole class sample under **`facterRegime=shared`** (the byte-identical-class premise the parity oracle uses; `varied` is a separate smaller-core bound). **VALIDATED (Task-0, `2a-baseline.md`):** class = 96-host agent class (`axon-synth-004…099`), `archHost=004`, total 240 units, **sharedKeys=212, delta=28** (per-host `acme-<hostname>` unique keys + `persist-…`/`frr`/`nftables`/`networkd`/`dbus`/`polkit`/`tailscaled` hostname-embedding); `nftables.service ∈ deltaKeys` ✓.
- **PURE `builtins.*` ONLY inside the `--apply` (Reviewer Fix #4, BLOCKER).** The apply lambda `ncs: …` receives the `nixosConfigurations` attrset; **`lib` is NOT in scope** (not a builtin; `ncs.<h>.config.lib` is the NixOS lib-option namespace, lacks `genAttrs`). Every existing harness apply (`parity-oracle.sh:29`, `lib-test.sh:16`, `force-count.sh:31`) is pure-builtins — match that. Substitutions: `lib.genAttrs ks f` → `builtins.listToAttrs (map (k: { name = k; value = f k; }) ks)` (bind once as `mk = ks: f: …`); no `builtins.take`/`drop` exist ⇒ **bash splices the exact M-host list literal per eval** (`hosts` IS the M-sublist for that eval); `builtins.elem`/`head`/`elemAt`/`mapAttrs`/`deepSeq`/`listToAttrs` all exist.
- **Archetype:** `archUnits = mk sharedKeys (k: (realUnits archHost)."${k}")` — the class's shared-core units (`archHost` = a fixed class member, spliced). **One let-bound value** forced exactly once (as element 0 of the 2a list); the per-host references then reuse the forced value-pointers (free).
- **2a per-host (SYMMETRIC, `removeAttrs` form — Task-0-validated):** `hostUnits2a h = archUnits // builtins.removeAttrs (realUnits h) sharedKeys`. Use `removeAttrs … sharedKeys`, NOT `genAttrs deltaKeys` — it handles per-host-UNIQUE keys (each host's own `acme-<hostname>` units, absent on others) and makes the identity check exact by construction (Task-0 verified `2a-assembled == vanilla`, `identical=true`, 225 keys). **Every host (including `archHost`) pays its own Δ** — do NOT special-case host0 (Reviewer Fix #3). Forcing the non-shared units still drags host h's `systemd.units` module-merge spine (separate fixpoint) — that residual is **paid in BOTH assemblies** (Gate-B's per-member WHNF bound, NOT something 2a removes). The saving = the 212 class-invariant units' **deep derivation construction**, paid M× in vanilla, once in 2a. **MEASURED (Task-0): marginal 21.72M → 8.76M/host (~60% collapse), saving ~12.96M/host, byte-identical.**
- **Two assemblies, ONE eval each, `canonicalize=false`.** The script splices M + the chosen assembly into a **single selected expression** (NOT an attrset-of-lambdas `{ vanilla=…; twoA=…; }` — that prints `<LAMBDA>` and measures nothing, Reviewer Fix #10):
  - `vanilla = builtins.deepSeq (map realUnits hosts) "ok"`
  - `twoA = builtins.deepSeq ([ archUnits ] ++ map (h: archUnits // builtins.removeAttrs (realUnits h) sharedKeys) hosts) "ok"`
  - `saving(M) = copies(vanilla) − copies(twoA)` at the spliced M (each measured by its own `synth_measure_reps`; cache-bust + eval-cache-off make them independent; the nixpkgs base ~28.96M is built within each and cancels in the subtraction).
- **Splice unit-key names with `json.dumps(k)`, NOT `f'"{k}"'` (Task-0 BLOCKER).** systemd unit names contain backslash escapes (e.g. `persist-persist-etc-machine\x2did.service`); a raw splice drops the `\` ⇒ `attribute … missing` at the first force. `json.dumps` emits a valid Nix string literal (escapes `\` and `"`). `vanilla` is immune (it uses `mapAttrs`, no key splicing); `twoA`/`archUnits`/`sharedKeys` splice keys ⇒ must escape.
- **Soundness gate (per-key, every sweep host) — ZERO exclusions (Reviewer Fix #8):** before trusting a sweep, assert `forall h, k∈sharedKeys: realUnits(h).${k}.drvPath == archUnits.${k}.drvPath`, with **no carve-outs**. If any shared key diverges on any host → not truly class-invariant → **reject**. The known `nftables.service` out-of-axis residual must NOT be excluded here: it differs host0-vs-host1, so Δ-discovery files it into `deltaKeys` automatically (recomputed per host, never shared) — and the gate explicitly **asserts `nftables.service ∈ deltaKeys`** (a positive natural-divergence check) rather than papering over it in the shared set. (Only the whole-map *fingerprint* in `parity-oracle.sh` legitimately excludes nftables, because it hashes Δ too; the per-key 2a gate must not.) This is the parity oracle applied at key granularity.

**Honest bounds (must appear verbatim-in-spirit in the evidence report — do not bury):**
1. **Intra-process only.** `archUnits` shared within ONE eval (fleet flake-check / deploy-plan / CI). Across separate `nix eval` it is recomputed ⇒ Plane 2b (gen-rebuild content-addressed, keyed by per-class selection hash) — deferred keystone.
2. **Units proxy, not full toplevel.** Shares rendered units; a full `toplevel` also has class-core + identity in /etc, activation, boot — same principle, more surface. The units result is the **lower bound** on the win.
3. **Production needs den-hoag.** Vanilla `nixosSystem` can't be handed a pre-resolved class core; assembling per-host toplevels from a shared archetype IS the §8a "inject at `host.instantiate`" seam. The PoC demonstrates the saving; production wiring is the den-hoag integration.
4. **drvPath equality = OUTPUT shareability;** the eval-work saving IS the copies decomposition, never drvPath alone. Stacks multiplicatively with Determinate parallel eval (~3.7×, verbatim nixpkgs).
5. **`marginal_2a` ≠ 0.** It includes each host's `systemd.units` module-merge spine residual (paid in both — likely the whole systemd-module spine, not "1-2 units"; measure, don't assume). Report it as measured; the headline is `saving(N)` + the per-host marginal **collapse**, not "free."
6. **Headline framing (Reviewer Fix #7): the PoC *identifies* shareable eval-work (an upper bound on the achievable saving), realized in production via the den-hoag inject-at-`instantiate` seam — NOT "work saved by a mechanism that ships today."** The harness models the injection (reuse the class archetype for all members); production wiring is den-hoag. State it as "shareable work identified, byte-identical-gated," so the number isn't read as an already-available speedup.

**Conventions:** explicit `git add <file>` by name; commit in the worktree with `PREK_ALLOW_NO_CONFIG=1`; never `git stash` in the worktree (user's stashes live there); every script gets a `tests/<name>-test.sh` (harness convention); evidence → papers archive, never committed in-repo; `.tasks.json` is the durable tracker (native CC tasks unused — the pre-commit-check-tasks hook blocks commits when they're open); format synth `.nix` with the direct `nixfmt` binary (`nix fmt` hangs on this flake). N>10 needs `ulimit -s unlimited` + `--option max-call-depth 1000000` (lib.sh handles it).

---

### Task 0: pick the class + discover Δ, re-confirm the baseline marginal

**Goal:** Identify the largest same-class host set at the sweep scales, discover the axis-dependent `deltaKeys` (one-time two-host diff), confirm `sharedKeys` are parity-clean, and re-confirm the ≈21.7M vanilla marginal — the numbers `2a-share.sh` is built against.

**Files:**
- Read: `synth-measure/{lib.sh,share-ratio.sh,partition.py,parity-oracle.sh}`; `modules/den/synth/{canonicalize.nix,factory.nix,skeleton.nix}`.
- Create (papers): `analysis/experiments/synthetic-fleet/2a-baseline.md`.

**Acceptance Criteria:**
- [ ] Largest same-class group identified at N=10/50/100 (via `.#den-debug.classKey` + `partition.py`); the chosen class + its member list recorded.
- [ ] `deltaKeys` discovered by diffing host0 vs host1 (same class) real units drvPaths; recorded with the key names; confirmed to be axis-dependent (hostname/secret/address-bearing), consistent with the 13-key canonical axis.
- [ ] `sharedKeys` parity-clean across ≥3 same-class hosts (every shared key drvPath-identical to `archHost`), **zero exclusions** (Reviewer Fix #8); `nftables.service` asserted **∈ `deltaKeys`** (its host-varying ruleset divergence lands it there by construction — assert, don't exclude).
- [ ] **Per-key laziness micro-check (Reviewer Fix #1 — the load-bearing assumption, gate the whole PoC on it):** force-count ONE Δ-key vs the full host units map (`force-count.sh`-style) and assert `copies(force one Δ key) ≪ copies(force full host)`. This proves `(realUnits h)."${k}"` constructs only that unit's derivation, not all ~225 — the premise the entire saving magnitude rests on. If it FAILS (a strict aggregation pulls all units when one key is read), the PoC degrades to an honest null (saving≈0), NOT a fake win — but the number must not be reported until this check is green.
- [ ] Vanilla marginal re-confirmed ≈21.7M (base + (M−1)·marginal), matching the PoC-spec table within noise.

**Verify:** `2a-baseline.md` has the chosen class, the `deltaKeys`/`sharedKeys` split, the parity-clean check, and the re-confirmed marginal.

**Steps:**
- [ ] **Step 1:** `SYNTH_N=100 bash synth-measure/share-ratio.sh` → the partition; pick the largest class; capture its members at N=10/50/100.
- [ ] **Step 2:** one eval — force host0 + host1 (same class) real units drvPath maps; compute `deltaKeys`/`sharedKeys` in python; record. (Reuse the `parity-oracle.sh:29` `fp`-style mapAttrs but return the per-key map, not its hash.)
- [ ] **Step 3:** parity-clean check — for 3 same-class hosts, assert all `sharedKeys` drvPath-equal to `archHost`, **no exclusions**; assert `nftables.service ∈ deltaKeys`. Record any divergence (a divergent shared key = a host not truly class-invariant → it must move to Δ or the class is wrong).
- [ ] **Step 4: per-key laziness micro-check** — `copies(deepSeq (realUnits h)."${oneDeltaKey}")` vs `copies(deepSeq (realUnits h))` (full map); assert the former ≪ the latter. Gate the PoC on this (Reviewer Fix #1).
- [ ] **Step 5:** re-confirm the vanilla marginal at M=1→2→3 (copies via `synth_measure_reps`); write `2a-baseline.md`.

---

### Task 1: `synth-measure/2a-share.sh` — the vanilla-vs-2a copies differential, parity-gated

**Goal:** The measurement script: one eval, two assemblies (vanilla full vs 2a archetype+Δ), copies differential, with the per-key parity gate that rejects any non-class-invariant shared key.

**Files:**
- Create: `synth-measure/2a-share.sh`.
- Read: `synth-measure/{lib.sh,lib_stats.py}` (reuse `synth_measure_reps` + median/IQR; do not re-implement the eval contract).

**Acceptance Criteria:**
- [ ] Sources `lib.sh`; uses `synth_measure_reps` for copies (NIX_SHOW_STATS, eval-cache-off, cache-bust); no bespoke eval path.
- [ ] Apply expression is **pure `builtins.*`** (no `lib.*` — not in `--apply` scope, Reviewer Fix #4); `deltaKeys`/`sharedKeys`/`hosts` (M-sublist)/`archHost` spliced as literals (re-derived at run start so the script is self-contained); `archUnits` one let-bound value (forced once); `twoA` is **symmetric** (every host incl `archHost` pays `archUnits // delta h`, Reviewer Fix #3); each eval ends in ONE selected assembly expression (not an attrset-of-lambdas, Reviewer Fix #10).
- [ ] **Parity gate fires before measuring, ZERO exclusions (Reviewer Fix #8):** asserts every `sharedKey` drvPath-identical to `archUnits` across all sweep hosts; asserts `nftables.service ∈ deltaKeys`; on ANY divergence it ERRORS and reports no saving.
- [ ] Reports per M: `copies_vanilla`, `copies_2a`, `marginal_vanilla`, `marginal_2a`, `saving(M) = copies_vanilla − copies_2a`; honors `SYNTH_N`.
- [ ] Determinism: copies stable across reps (cache-bust working); the script fails loudly if `ok:false` (eval error) instead of reporting a fake zero.

**Verify:** `SYNTH_N=10 bash synth-measure/2a-share.sh` → prints the differential table; `marginal_2a < marginal_vanilla` strictly; parity gate green.

**Steps:**
- [ ] **Step 1: re-derive `deltaKeys`/`sharedKeys`** at run start (Task-0 logic) so the script needs no external state; emit them for the record.
- [ ] **Step 2: parity gate (pure-builtins apply, zero exclusions)** — eval the per-key `sharedKey` drvPaths for every sweep host vs `archUnits`; python asserts identity with **no carve-outs**; separately assert `nftables.service ∈ deltaKeys`; ERROR + exit on any divergence.
- [ ] **Step 3: build the apply expression — PURE `builtins.*`, ONE selected assembly per eval** (Reviewer Fixes #4 BLOCKER + #10 + #3). Bash splices the **M-host list literal** (`hosts`), `archHost`, `sharedKeys`, `deltaKeys`, and selects `vanilla` xor `twoA` as the **final expression** (no attrset-of-lambdas — that returns `<LAMBDA>` and measures nothing). `lib` is NOT in scope; use only builtins:
  ```nix
  ncs:
  let
    hosts = [ "axon-synth-001" "axon-synth-002" ... ];   # spliced = the M-host class sublist for THIS eval
    archHost = "axon-synth-001";                          # spliced fixed class member
    sharedKeys = [ ... ]; deltaKeys = [ ... ];            # spliced
    mk = ks: f: builtins.listToAttrs (map (k: { name = k; value = f k; }) ks);
    realUnits = h: builtins.mapAttrs (_: u: u.unit.drvPath or null) ncs.${h}.config.systemd.units;
    archUnits = mk sharedKeys (k: (realUnits archHost).${k});          # forced once
    delta = h: mk deltaKeys (k: (realUnits h).${k});
  in
    # bash emits ONE of these two as the trailing expression:
    builtins.deepSeq (map realUnits hosts) "ok"                                    # vanilla
    # builtins.deepSeq ([ archUnits ] ++ map (h: archUnits // delta h) hosts) "ok" # twoA (symmetric: EVERY host pays Δ)
  ```
  Measure the vanilla-apply and the twoA-apply each via `synth_measure_reps` at the spliced M. Apply the same pure-builtins style to the Step-2 parity-gate apply (no `lib.*` there either).
- [ ] **Step 4: report** the differential table (`lib_stats.py` for median/IQR); fail on `ok:false`.

---

### Task 2: sweep N {2,10,50,100} × K classes — saving(N) + marginal collapse

**Goal:** Run the differential across scales and ≥2 classes; produce the saving curve and the per-host marginal collapse — the headline numbers.

**Files:**
- Run-only: `synth-measure/2a-share.sh` (SYNTH_N sweep).
- Create (papers): extend `analysis/experiments/synthetic-fleet/2a-baseline.md` → `2a-result.md` with the curve.

**Acceptance Criteria:**
- [ ] `saving(N)` reported for N ∈ {2,10,50,100}; grows ~linearly in N (each added same-class host saves ≈ the shared deep-construction fraction of 21.7M).
- [ ] `marginal_2a` reported and ≪ `marginal_vanilla` (the spec's acceptance: strictly smaller, by a large factor); the per-host marginal collapse quantified (e.g. 21.7M → X M).
- [ ] Run on ≥2 distinct classes (e.g. server-base and agent) to show it's not a single-class artifact.
- [ ] If `marginal_2a` is NOT ≪ vanilla (module-merge dominates the units marginal), report it as the **honest result** + the decomposition (how much of 21.7M is shared deep-construction vs un-liftable WHNF) — that is still a valid finding, not a failure to hide.

**Verify:** `2a-result.md` has the saving(N) table for N∈{2,10,50,100} on ≥2 classes + the marginal-collapse number.

**Steps:**
- [ ] **Step 1:** sweep `SYNTH_N` ∈ {2,10,50,100}; capture copies_vanilla/copies_2a/saving.
- [ ] **Step 2:** repeat on a second class.
- [ ] **Step 3:** tabulate saving(N) + marginal collapse; write `2a-result.md` with the honest decomposition + the 5 bounds.

---

### Task 3: `tests/2a-share-test.sh` — gate teeth + monotonic saving

**Goal:** Lock in the PoC's soundness and the headline claim with a committed test (harness convention): the parity gate REJECTS a planted out-of-axis leak, 2a units are drvPath-identical to vanilla, and saving grows with N.

**Files:**
- Create: `synth-measure/tests/2a-share-test.sh`.

**Acceptance Criteria:**
- [ ] **Identity:** asserts the 2a-assembled units map is drvPath-identical to the vanilla full map for a sweep host (no soundness loss — same per-key drvPaths).
- [ ] **Synthetic teeth:** substitute a non-identical value into a key the gate treats as `shared` ⇒ the parity gate MUST error/reject (exercises the "a sharedKey diverged" reject path directly; `plantLeak`'s `synth-leak.service` is a NEW per-host key that Δ-discovery files into `deltaKeys`, so it does NOT by itself hit the reject path — the synthetic substitution does).
- [ ] **Natural teeth (Reviewer Fix #9):** assert `nftables.service ∈ deltaKeys` (a REAL out-of-axis divergence correctly isolated to Δ, not silently shared) — a real-world soundness check, not only a synthetic one.
- [ ] **Monotonic:** `saving(50) > saving(10) > 0`.
- [ ] Test passes via the daemon path (default) and is listed alongside the other `tests/*`.

**Verify:** `bash synth-measure/tests/2a-share-test.sh` → all assertions PASS; flipping the leak makes the gate REJECT.

**Steps:**
- [ ] **Step 1:** identity assertion (2a map == vanilla map per-key).
- [ ] **Step 2:** synthetic-teeth assertion (substitute a non-identical value into a `sharedKey` ⇒ gate rejects) + natural-teeth assertion (`nftables.service ∈ deltaKeys`).
- [ ] **Step 3:** monotonic-saving assertion at small N.

---

### Task 4: evidence + tracker + memory + handoff to S1

**Goal:** Commit the PoC + evidence, update the durable tracker and the hola memory with the first hard saving number, and hand off to S1 (the next sub-project in the band).

**Files:**
- Commit (worktree): `synth-measure/2a-share.sh`, `synth-measure/tests/2a-share-test.sh`, any `scale.json` field additions.
- Commit (papers): `analysis/experiments/synthetic-fleet/2a-baseline.md`, `2a-result.md`; this plan's `.md.tasks.json`.
- Modify: `RESUME-fleet-architecture.md` (build-order item 3 — Plane-2a PoC done + the number); memory `project_hola.md` CURRENT STATE tail (in place).

**Acceptance Criteria:**
- [ ] `2a-share.sh` + test committed on `demo/persist-claims-open-emit` (throwaway branch; den UNCHANGED); commit message states the measured saving + the 5 bounds (no co-authored-by).
- [ ] `2a-result.md` is the durable headline: `marginal_vanilla` vs `marginal_2a`, `saving(N)` curve, marginal-collapse %, the honest decomposition, the 5 bounds.
- [ ] `.md.tasks.json` Tasks 0-4 = completed.
- [ ] `project_hola.md` CURRENT STATE updated **in place** (Plane-2a PoC done + the number; next = S1) per the hub's tail-replace hygiene.
- [ ] Decision/result surfaced to the user: the measured saving + whether it justifies the den-hoag injection seam (it should — that's the value test) → proceed to S1.

**Verify:** `git -C <worktree> log --oneline -1`; `2a-result.md` present in papers; memory tail reflects the number.

**Steps:**
- [ ] **Step 1:** commit the script + test (worktree) + the evidence (papers).
- [ ] **Step 2:** update `.md.tasks.json` + `RESUME-fleet-architecture.md` + `project_hola.md` tail (in place).
- [ ] **Step 3:** report the headline number to the user; proceed to S1 (`plans/2026-06-28-fleet-seam-s1-per-sid-hostconfig.md`, already written + reviewed — apply the 3 reviewer fixes first).
