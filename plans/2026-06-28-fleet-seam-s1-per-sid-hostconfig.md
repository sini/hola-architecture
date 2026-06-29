# Fleet Seam S1 — kill the global `hasAnyConfigThunk` flag → per-sid lazy `hostConfigFor` Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove den's fleet-wide all-or-nothing `hasAnyConfigThunk` boolean (`resolve.nix:393-408`) and the eager `specsByHost` arming it gates, replacing them with a cheap structural host-scope **set** (`hostConfigScopeIds`, for membership) plus an always-lazy memoized **`hostConfigFor sid`** (for value reads), so a config-dependent cross-host emit forces only the peers it actually collects from — killing the latent eager-consumer footgun without changing the (already-correct) per-edge cost.

**Architecture:** den's fx resolver currently scans *every* scope's raw imports for any `{ config, … }` thunk; one hit (even a purely *local* age-secret emit) flips a global boolean that builds a `hostConfigs = mapAttrs (full nixosSystem) specsByHost` over the entire fleet. The map is lazy so nothing forces it today, but the boolean + the `specsByHost` listToAttrs are O(fleet) eager work and a latent blow-up: any future eager consumer forces every peer. This is spec §8a **S1** (`2026-06-25-fleet-eval-sharing-architecture.md`). The fix factors `hostConfigs` (one map, two roles) into a structural **key-set** used for the `?`-membership / owner-walk tests and a **lazy per-sid builder** used only when a config-dependent collected/broadcast edge resolves against a peer. No surface change — `pipe.from … collect/collectAll` is untouched; this removes one internal flag and is backward-compatible for every existing closed emit. S2's `pipe.reads` cone-expander and the unscoped-`collectAll` lint are *separate* later sub-projects; S1 only removes the global arming.

**Tech Stack:** Nix (den fx algebraic-effects resolver `nix/lib/aspects/fx/`); den CI test suite (`just ci`, nix-unit, `templates/ci` + `deadbugs/` regression configs); the synthetic-fleet harness (`modules/den/synth/**` + `synth-measure/**` on the nix-config worktree) for force-count measurement; real axon-02/03 for byte-identical parity.

---

## Context the implementer needs (read before Task 0)

**The seam, exactly (den `@11866c16`, post-`#623 pipe.broadcast`):**

- `nix/lib/aspects/fx/resolve.nix`
  - `:392` `isConfigDependent = val: builtins.isFunction val && (builtins.functionArgs val) ? config;` — the boundary predicate. **Keep verbatim.**
  - `:393-408` `hasAnyConfigThunk` — eager `builtins.any` over **all** `scopedClassImportsRaw`. **DELETE.**
  - `:415-468` `hostConfigs = if !hasAnyConfigThunk then null else <let allInstantiates / specsByHost / mkArgs in lib.mapAttrs (_: spec: (spec.instantiate (mkArgs spec)).config) specsByHost>`. This is the **B′ re-entry** (each peer's full config, built over the `hostConfigs`-NULL drained contexts — cycle-broken, do **not** disturb that cycle reasoning). **REPLACE** with `hostConfigScopeIds` (set of keys of `specsByHost`) + `hostConfigFor` (lazy memoized `sid: (specsByHost.${sid}.instantiate (mkArgs specsByHost.${sid})).config`).
  - `:475-481` `augmentedScopeContexts = assemblePipes { inherit scopeContexts hostConfigs …; }` — the consumer call. **Thread the new pair instead of `hostConfigs`.**
  - `:507-514` `augmentedScopeContextsNoCfg = assemblePipes { … hostConfigs = null; … }` — the cycle-breaking NULL pass that *builds* B′. **Leave its `hostConfigs = null` exactly as-is** (it must stay config-free; see `:483-506` comment). It tells `assemblePipes` "no peer configs on this path" — the new code must preserve that "null ⇒ defer" semantics (Task 2).
  - `:903` `bprimeEdges = lib.optionals (hostConfigs != null) (…)` — a `hostConfigs != null` guard. **Re-express** against the new representation (Task 1, step 5).
- `nix/lib/aspects/fx/assemble-pipes.nix` (the consumer; `hostConfigs` is a `?`-defaulted-`null` param threaded through every stage)
  - `:124-182` `producerConfigs = { hostConfigs, scopeContexts, scopeParent, scopeEntityClass }: scopeId: …` — three branches keyed on the map: `hostConfigs == null` (defer/empty), `hostConfigs ? scopeId` (this scope OWNS a config — a host), else `findOwner` walks `scopeParent` doing `hostConfigs ? sid` membership then reads `hostConfigs.${ownerScope}`. **This is the load-bearing consumer.** The `?`-membership tests must move to `hostConfigScopeIds` (set, no force); the `.${sid}` value reads to `hostConfigFor sid`.
  - `:189-216` `resolveEntry = hostConfigs: producerConfigFor: …: entry:` — `if isConfigDependent entry then (if hostConfigs == null then [ entry ] (defer-local) else <resolve via producerConfigFor>)`. The `hostConfigs == null` here = "this crossing path carries no peer configs" (the NULL pass). **Preserve a `null`/empty sentinel meaning the same thing.**
  - `:233-235` `resolveThunks = hostConfigs: producerConfigFor: …` — threads the param down.
  - `:404, :538, :577, :626, :802, :868` — each stage entry has `hostConfigs ? null,` in its arg set and passes it on (`:427, :561, :601, :643, :808, :894, :993, :1015, :1077, :1095`). All are pass-through threading sites.
  - `:751 / :944-946` `markConfigThunks` (incl. `#623` `markedExposed` for broadcast) — marks **local** config-dependent values for in-fixpoint resolution. **Local marking is orthogonal to S1** (it never reads the peer map); leave it, but confirm the broadcast tests stay green.
- `nix/lib/aspects/fx/spawn-node.nix:115` `hostConfigs = null;` — spawned (relocated) nodes pass null = config-free. **Keep null** (a spawned shared node must not arm peer-config resolution); under the new threading this is the "defer" sentinel.

**The two roles `hostConfigs` plays (why the split is sound):**
1. **Membership / structure** — `hostConfigs ? sid` and `findOwner` ask only *"is `sid` a host scope that owns a config?"*. That is the **key-set** of `specsByHost`, computable **without building any config** (`specsByHost` keys come from `allInstantiates` specs, not from forcing `.instantiate`).
2. **Value** — `hostConfigs.${sid}` reads the peer's resolved `config`. Only this needs the lazy per-sid build.

Splitting (1) into a forced-cheap set and (2) into a lazy memoized fn means the *structure* is always available (so `producerConfigs` branches correctly) while *no peer config is built until a config-dependent edge actually resolves against it* — which is precisely the footgun removal. `lib.mapAttrs` already memoizes per key, so `hostConfigFor = sid: builtConfigs.${sid}` where `builtConfigs = lib.mapAttrs (…) specsByHost` preserves memoization for free; the win is that `specsByHost` and `builtConfigs` are no longer gated by a global boolean and are never *armed* eagerly — they're only constructed structurally (keys) and forced per-sid (values) on demand.

> **REVIEWER FIX 1 (load-bearing, do not skip).** `hostConfigScopeIds` **MUST be an attrset** — `lib.genAttrs (builtins.attrNames specsByHost) (_: true)` — tested with `hostConfigScopeIds ? sid` (O(1) hash lookup). It must **NOT** be a list `builtins.attrNames specsByHost` tested with `builtins.elem` (O(N)). The old `hostConfigs ? sid` is O(1); `producerConfigs.findOwner` (assemble-pipes.nix:161-168) recurses the parent chain doing one membership test per ancestor, and `producerConfigFor` runs once per config-dependent collected entry — so a list + `elem` is O(N·D) per entry ⇒ O(N²·D) for a fleet-wide config-dep collect (the central-persist-claim shape), a self-inflicted scale regression in the *exact* open-emit hot path S1 exists to keep cheap. The N≤100 measurement (Task 4) is too small to reveal an O(N²) term, so a list form would ship silently behind a "footgun killed" banner. Keep the structural set an attrset; keep `hostConfigFor` separate for values.

**Key-set restriction (spec §8a S1: "`specsByHost`'s key-set restricted to the union of config-dependent collect-edge-matched scopes"):** the minimal, behavior-preserving form keeps `specsByHost` keyed over all output-bearing instantiates (its current key-set) but **never forces a value** except via `hostConfigFor`. Whether to *further* prune the key-set to only config-dep-collect-matched sources is an **optimization that requires analyzing the collected edges** and is **explicitly deferred to a step gated on measurement** (Task 1 Step 6 — only do it if Task 3 shows the *structural* `specsByHost` construction is itself a measurable cost; the lazy `builtConfigs` already removes the forcing cost). Do not over-build: the primary deliverable is "no global flag, no eager value forcing."

**Den-branch / override base:** the nix-config worktree pins `den.url = "github:sini/den/fix/broadcast-home-pool-to-host"` (the unmerged `#625` replicated-home fix), **not** `denful/den` main. S1 must be validated against a den that has BOTH that fix (so the worktree evaluates) AND S1. Base the S1 branch on `fix/broadcast-home-pool-to-host` for harness compatibility; the S1 diff stays a clean, cherry-pickable change on `resolve.nix`/`assemble-pipes.nix` (the fix branch touches spawn/broadcast, not `hasAnyConfigThunk`) for the eventual `denful/den` PR. Iterate with `--override-input den path:/home/sini/Documents/repos/den` against a local den worktree so no github round-trips are needed.

**Conventions (honor the feedback memories):**
- Explicit `git add <file>` by name; never `-A`/`.`.
- den format: `nix develop -c just fmt` — but if `nix fmt` hangs (synth-flake daemon issue), format touched `.nix` with the direct `nixfmt` binary.
- den CI: `just ci` (suites) / `just ci <suite>.<test>` (specific, with traces; summary on last line).
- Use `inherit` for hyphenated identifiers; idiomatic Nix; preserve provenance citations + the `§A #8/#2/#7` B′ comments verbatim.
- No co-authored-by trailer; no docs committed in-repo (evidence → this papers archive).
- Worktrees under `.worktrees/` in repo root.
- Caveman-lite to subagents; opus for this (non-mechanical fixpoint surgery).

---

### Task 0: den S1 worktree + local override + pre-S1 baseline capture

**Goal:** A den worktree on an S1 branch wired into the synth harness via local override, plus the *pre-change* force-count/structural baseline the S1 win is measured against.

**Files:**
- Create: den worktree `~/Documents/repos/den/.worktrees/s1-per-sid-hostconfig` (branch `feat/s1-per-sid-hostconfig` off `fix/broadcast-home-pool-to-host`).
- Read: `synth-measure/lib.sh`, `synth-measure/scale.json`, `synth-measure/1b-resolve.sh` (the eval contract + `globalTrigger` knob).
- Create (papers, not committed in-repo): `analysis/experiments/synthetic-fleet/s1-baseline.md`.

**Acceptance Criteria:**
- [ ] den worktree exists on `feat/s1-per-sid-hostconfig`; `git -C` shows clean tree off the fix branch.
- [ ] The synth harness evaluates against the local den override (`--override-input den path:<den-worktree>`) byte-identically to the github pin (sanity: one `1b-resolve.sh` check passes unchanged).
- [ ] Baseline captured at N=10/50/100 for three configurations, recorded in `s1-baseline.md`: **(A)** `globalTrigger=true` (collectAll synthOpenTrigger), **(B)** one scoped cone only (`light-emit`, scoped collect — the persist-claims shape), **(C)** closed-only / no config-dep emit. Metrics: NIX_SHOW_STATS `nrFunctionCalls` + `nrThunks` + copies (deterministic) and whether `hostConfigs`/`specsByHost` machinery is structurally constructed.

**Verify:** `bash synth-measure/1b-resolve.sh` (or the relevant driver) against `--override-input den path:<worktree>` → same PASS as the github pin; `s1-baseline.md` has the 3×3 table.

**Steps:**
- [ ] **Step 1: create the den worktree off the harness's den base.**
  ```bash
  cd /home/sini/Documents/repos/den
  git worktree add .worktrees/s1-per-sid-hostconfig -b feat/s1-per-sid-hostconfig fix/broadcast-home-pool-to-host
  git -C .worktrees/s1-per-sid-hostconfig log --oneline -1
  ```
- [ ] **Step 2: confirm local override evaluates identically.** Pick the simplest harness check; run it once with the github pin and once with `--override-input den path:/home/sini/Documents/repos/den/.worktrees/s1-per-sid-hostconfig`; diff results (must match — den is unchanged at this point).
- [ ] **Step 3: capture the pre-S1 baseline** (A/B/C × N=10/50/100). Reuse `lib.sh`'s eval-cache-off + NIX_SHOW_STATS path; `ulimit -s unlimited` + `--option max-call-depth 1000000` (den class-collector recursion past N≈10). Record in `s1-baseline.md`. **No commit of den yet.**

---

### Task 1: factor `hostConfigs` into `hostConfigScopeIds` (set) + `hostConfigFor` (lazy) in `resolve.nix`

**Goal:** Delete the global `hasAnyConfigThunk` boolean; expose a structural host-scope key-set and an always-lazy memoized per-sid config builder; thread the new pair into both `assemblePipes` call-sites; keep the B′ NULL-pass cycle and `bprimeEdges` guard correct.

**Files:**
- Modify: `nix/lib/aspects/fx/resolve.nix:389-518` (the `hasAnyConfigThunk`/`hostConfigs` block + the two `assemblePipes` calls) and `:903` (`bprimeEdges` guard).

**Acceptance Criteria:**
- [ ] `hasAnyConfigThunk` no longer gates `hostConfigs` building (the footgun): the scan is **renamed** `anyConfigDepThunk` and used **only** for the `bprimeEdges` guard (Reviewer Fix 2). Building is now lazy/per-sid, ungated.
- [ ] `hostConfigScopeIds` = an **attrset** `lib.genAttrs (builtins.attrNames specsByHost) (_: true)` (O(1) `?`-membership — NOT a list + `builtins.elem`, see Reviewer Fix 1), computed without forcing any `.instantiate`.
- [ ] `hostConfigFor` = `sid: builtConfigs.${sid}` where `builtConfigs = lib.mapAttrs (_: spec: (spec.instantiate (mkArgs spec)).config) specsByHost` (per-sid memoized, never armed by a flag).
- [ ] Both `assemblePipes` calls receive the new pair; the `augmentedScopeContextsNoCfg` pass still signals "no peer configs" (its config-free contract `:483-506` intact).
- [ ] `bprimeEdges` guard tied to `anyConfigDepThunk` (config-dep thunk **present**), NOT host-presence (`hostConfigScopeIds != {}`). A closed-only fleet has hosts but no config-dep thunk ⇒ old guard returned `[ ]` and built **no** `specsByHost`; a host-presence guard would force `specsByHost` + construct inert (deduped-away) B′ edges on every closed eval. Keep it gated on config-dep presence so closed paths stay zero-cost (Reviewer Fix 2).
- [ ] den evaluates (`nix flake check` in `templates/ci` or the engine entrypoint) without "infinite recursion" — the B′ cycle reasoning is preserved.

**Verify:** den CI subset for the fx resolver + cross-host pipes passes (full gate in Task 3). `nix eval` of a config-dep-collect template resolves; a closed-only template is byte-identical to pre-change.

**Steps:**
- [ ] **Step 1: write/extend a den regression test that pins the footgun behavior** (TDD-first). Add a `templates/ci` (or `deadbugs/`) fixture with a *local-only* config-dep emit (mirrors the two real-axon age-secret emits) and assert that resolving it does **not** require building any *peer* config — i.e. a peer whose `.instantiate` throws is NOT forced by the presence of an unrelated local config-dep emit. (Pre-S1 this passes vacuously because the map is lazy; the test's job is to *lock in* that S1 preserves it while removing the global arming. Pair it with a config-dep *scoped collect* fixture asserting only the matched peer is forced.) Run: it should be green pre-change (laziness) — that is the invariant S1 must not regress.
- [ ] **Step 2: rename `hasAnyConfigThunk` → `anyConfigDepThunk` (`:393-408`); keep the scan body verbatim.** It NO LONGER gates `hostConfigs` building (now lazy via `hostConfigFor`) — its only remaining consumer is the `bprimeEdges` guard (Step 5). This is the footgun removal: a config-dep thunk anywhere no longer *arms* peer-config eval; the O(imports) presence scan only avoids inert B′ edge construction on closed fleets (Reviewer Fix 2).
- [ ] **Step 3: rewrite the `hostConfigs` block (`:415-468`)** as:
  ```nix
  # specsByHost: output-bearing instantiate specs keyed by host scope id.
  # Keys are structural (no .instantiate forced); values built lazily per-sid.
  specsByHost = <the existing :421-438 listToAttrs over allInstantiates — UNCHANGED>;
  mkArgs = <the existing :439-466 mkInstantiateArgs — UNCHANGED>;
  # Structural ATTRSET for membership / owner-walk (forces nothing). `?`-membership
  # is O(1); a list + `builtins.elem` would be O(N) ⇒ O(N²·D) in findOwner (Reviewer Fix 1).
  hostConfigScopeIds = lib.genAttrs (builtins.attrNames specsByHost) (_: true);
  # Lazy, per-sid memoized peer config (the B′ re-entry). No global flag arms it;
  # a peer config is built only when a config-dependent edge resolves against `sid`.
  builtConfigs = lib.mapAttrs (_: spec: (spec.instantiate (mkArgs spec)).config) specsByHost;
  hostConfigFor = sid: builtConfigs.${sid};
  # Config-dep-present predicate — KEPT (renamed from hasAnyConfigThunk), but now used
  # ONLY to gate bprimeEdges (Step 5), NOT to gate hostConfigs building. It no longer
  # arms peer-config eval (that is lazy via hostConfigFor) ⇒ the footgun is killed;
  # this O(imports) scan only avoids inert B′ edge construction on closed fleets.
  anyConfigDepThunk = <the existing :393-408 scan body — UNCHANGED, just renamed>;
  ```
  Preserve the full `§A #8/#2/#7` comment block (`:439-466, :483-506`) verbatim.
- [ ] **Step 4: thread the new pair into the two `assemblePipes` calls.** `augmentedScopeContexts` (`:475`) gets `hostConfigScopeIds` + `hostConfigFor` (drop `hostConfigs`); `augmentedScopeContextsNoCfg` (`:507`) keeps its "no peer configs" signal — pass an **empty** id-set + a `hostConfigFor` that is never consulted (the NULL contract: config-dep entries defer on this path). Decide the empty-signal representation in Task 2's interface (Step 1) and apply it identically here.
- [ ] **Step 5: re-express `bprimeEdges` (`:903`)** `lib.optionals (hostConfigs != null)` → `lib.optionals anyConfigDepThunk` — B′ edges exist iff a config-dep thunk is present (the OLD condition, since `hostConfigs != null` ⟺ `hasAnyConfigThunk`). Do **NOT** use `hostConfigScopeIds != {}` (host-presence) — that fires on closed fleets, forcing `specsByHost` + building inert (perHostEdges-deduped, `:886-888`) B′ edges that previously cost zero (Reviewer Fix 2). Confirm against `instantiate-edges.nix:11`.
- [ ] **Step 6 (DEFERRED — gated on Task 3): key-set pruning.** Only if Task 3 shows the *structural* `specsByHost`/`builtConfigs` *construction* (not forcing) is itself a measurable cost at N=100: restrict `specsByHost` keys to the union of scopes matched by config-dependent collect/broadcast edges. Otherwise skip (YAGNI — the lazy build already removes the forcing cost). Record the decision in the evidence.
- [ ] **Step 7: format + intra-task commit** (`nixfmt` direct if `nix fmt` hangs). Commit `resolve.nix` only once Task 2 makes the engine eval (these two files change atomically; if committing mid-way, do it after Task 2 step that restores a green eval). `PREK_ALLOW_NO_CONFIG=1` not needed in den (it has pre-commit); use `just fmt` then commit.

---

### Task 2: thread the (set, fn) pair through `assemble-pipes.nix` consumers

**Goal:** Replace every `hostConfigs`-map membership/value use in `assemble-pipes.nix` with the structural set + lazy fn, preserving the exact null/defer semantics, so the engine evaluates and behavior is unchanged.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` — `producerConfigs:133-182` (body; :124-132 is its comment), `resolveEntry:189-228` (config-dep half :189-216), `resolveThunks:233-235`, the two `resolveThunks` **value** call sites `:442` + `:833` (Reviewer Fix 5 — easy to miss; `grep -n 'hostConfigs' assemble-pipes.nix` is the backstop), and the stage-interpreter threading sites (`:404,:427,:538,:561,:577,:601,:626,:643,:802,:808,:868,:894,:993,:1015,:1077,:1095`).

**Acceptance Criteria:**
- [ ] `producerConfigs`: `hostConfigs == null` branch → preserved "defer/empty" via the empty-attrset sentinel `hostConfigScopeIds == {}`; `hostConfigs ? scopeId` → `hostConfigScopeIds ? scopeId` (O(1), NOT `builtins.elem`); `hostConfigs.${scopeId}` / `findOwner` membership + `hostConfigs.${ownerScope}` → `?`-membership + `hostConfigFor`.
- [ ] `resolveEntry`: the `hostConfigs == null` defer-local path triggers exactly when the NULL pass / spawn-node passes the empty signal — no config-dep collected entry resolves against a peer on a config-free path.
- [ ] Every stage interpreter threads the new pair (param rename `hostConfigs ? null` → the chosen interface; no orphaned references).
- [ ] `markConfigThunks` (local + `#623` broadcast `markedExposed`) is untouched and still marks local emits for in-fixpoint resolution.
- [ ] den engine evaluates end-to-end.

**Verify:** `nix flake check` in `templates/ci` (or engine entry) green; the Task 1 regression fixture + the existing cross-host/broadcast templates resolve identically.

**Steps:**
- [ ] **Step 1: choose the interface (do this first, apply everywhere).** Replace the single threaded `hostConfigs` arg with a pair `{ hostConfigScopeIds ? { }, hostConfigFor ? (_: throw "no peer config") }` — **`hostConfigScopeIds` is an ATTRSET** (Reviewer Fix 1). The "config-free path" (old `hostConfigs == null`) becomes `hostConfigScopeIds == { }` (and `hostConfigFor` never consulted). **Precondition for the `null ≡ {}` collapse (Reviewer Fix 3):** the equivalence holds because the old `== null` branch is reachable only when `!hasAnyConfigThunk` (no config-dep entry exists), and the old non-null-empty-map case (`hasAnyConfigThunk` true yet `specsByHost == {}` — a config-dep thunk exists but zero entities produce flake output) is a near-unreachable degenerate where old code resolves the entry against `config = {}` (likely throwing) while new code defers it. **The defer is the more-correct behavior; document it + add a regression assertion** rather than restoring resolve-against-empty. State the precondition (≥1 host produces output) in the comment that replaces the old `== null` comment. `resolveEntry`/`resolveThunks` need **only** `hostConfigScopeIds` (for the `== {}` test) — NOT `hostConfigFor` (all value resolution goes through `producerConfigFor`); do not thread the throwing `hostConfigFor` next to a path that never calls it (Reviewer Fix 4).
- [ ] **Step 2: rewrite `producerConfigs` (`:133-182`).** `if hostConfigScopeIds == { } then <empty>` ; `else if hostConfigScopeIds ? scopeId then { config = hostConfigFor scopeId; owner = hostConfigFor scopeId; … }` ; else `findOwner` walks `scopeParent` testing `hostConfigScopeIds ? sid` (O(1)), then `ownerCfg = if ownerScope == null then {} else hostConfigFor ownerScope`. Preserve the `parentArg`/`parentPath`/`name` nested-scope logic verbatim. **`hostConfigFor` lives here only** (the sole value consumer).
- [ ] **Step 3: rewrite `resolveEntry` (`:189-216`) + `resolveThunks` (`:233`)** to thread **only `hostConfigScopeIds`** (+ `producerConfigFor`, already built from `hostConfigFor` in `producerConfigs`); the `if hostConfigs == null then [ entry ]` defer becomes `if hostConfigScopeIds == { } then [ entry ]`. Keep the comment explaining the deferred-local pass-through. Update the two value call sites `:442` + `:833` (`resolveThunks hostConfigs …` → the threaded signal).
- [ ] **Step 4: thread through every stage interpreter** (the `:404…:1095` sites). Mechanical rename of the `hostConfigs ? null` param + its pass-throughs to the pair. Grep after: `grep -n 'hostConfigs' assemble-pipes.nix` should return only comments (or nothing) — no live `hostConfigs` value references.
- [ ] **Step 5: align `spawn-node.nix:115`** — its `hostConfigs = null;` becomes the empty-set signal (`hostConfigScopeIds = [ ];`), keeping spawned nodes config-free.
- [ ] **Step 6: format, eval, intra-task commit.** `just fmt`; `nix flake check` (`templates/ci`) green; commit `assemble-pipes.nix` + `resolve.nix` + `spawn-node.nix` together (atomic engine change) with a focused message.

---

### Task 3: den CI regression gate — full suite green

**Goal:** Prove S1 changes no observable den behavior: the full den test suite passes, with explicit attention to the cross-host / B′ / broadcast regressions.

**Files:**
- Run-only: `just ci` and targeted `just ci <suite>.<test>`; the `deadbugs/bprime-basedrain-crosshost.nix`, broadcast (`#623`), and cross-host pipe fixtures.

**Acceptance Criteria:**
- [ ] `just ci` full suite: same pass count as the pre-S1 baseline (den memory: ~1044/1044 — confirm the actual number on the fix branch first, then match it).
- [ ] `deadbugs/bprime-basedrain-crosshost` passes (the B′ drained-context variant-B witness).
- [ ] Broadcast (`#623`) + collect/collectAll cross-host templates pass.
- [ ] The Task 1 footgun-invariant fixture passes (only matched peers forced).

**Verify:** `just ci` final-line summary = full green, equal to the pre-change count on `feat/s1-per-sid-hostconfig`'s parent.

**Steps:**
- [ ] **Step 1: record the parent's pass count.** `git stash`-free: check out the diff's parent state mentally — run `just ci` on the branch *before* applying S1 (or note the count from a clean fix-branch run) to get the target number. (If already applied, temporarily `git -C <den-worktree> stash` is FORBIDDEN per conventions — instead diff against a second clean worktree of the fix branch.)
- [ ] **Step 2: run `just ci` on the S1 branch**; compare counts. Any delta → systematic-debugging skill, fix root cause (not a workaround), re-run.
- [ ] **Step 3: run the targeted cross-host/B′/broadcast tests with traces** (`just ci <suite>.<test>`) to confirm they pass on substance, not by skip.

---

### Task 4: synth + real-axon validation — footgun killed, byte-identical

**Goal:** Demonstrate S1's win (no fleet-wide arming for scoped/local config-dep emits) on the synthetic fleet at N=100, and prove zero behavioral drift on the real axon class.

**Files:**
- Run-only: `synth-measure/lib.sh` + `1b-resolve.sh` + the `globalTrigger`/scoped/closed `scale.json` configs (worktree, with `--override-input den path:<s1-worktree>`).
- Real axon: the `demo/persist-claims-open-emit` open-emit demo + `nixosConfigurations.<axon-host>.config.system.build.toplevel.drvPath`.
- Create (papers): `analysis/experiments/synthetic-fleet/s1-result.md`.

**Acceptance Criteria:**
- [ ] **Footgun killed:** the win is that peer-config **building** is no longer armed by a config-dep thunk's mere presence — NOT that the presence-scan disappears (it is kept as `anyConfigDepThunk` for the `bprimeEdges` guard, Reviewer Fix 2). Post-S1: config (C) closed-only builds **no** `specsByHost`/`builtConfigs` and no inert B′ edges (the `anyConfigDepThunk` guard is false ⇒ identical to baseline C, or strictly cheaper — confirm not *worse*); config (B) scoped-cone forces only the matched peer's `builtConfigs.${sid}`, not the fleet. Measure via NIX_SHOW_STATS copies vs `s1-baseline.md` (Task 0). **Honesty:** S1 does not reduce (B)'s already-correct matched-peer cost (Gate-A laziness handled that); it removes the *latent* fleet-wide arming + keeps closed paths zero-cost.
- [ ] **No regression on the worst case:** config (A) `globalTrigger=true` (collectAll) still resolves correctly (it *should* force the fleet — that is the shape S2's lint will reject; S1 must not break it). Result parity with baseline (A).
- [ ] **Real-axon byte-identical:** the persist-claims open-emit demo resolves to the same axon-class result as pre-S1; `toplevel.drvPath` for the real axon host(s) is unchanged (`nix-diff` clean).
- [ ] Results + the before/after table written to `s1-result.md`.

**Verify:** `s1-result.md` shows B/C footgun-killed vs baseline, A unchanged, real-axon `drvPath` identical (string match).

**Steps:**
- [ ] **Step 1:** re-run the Task-0 A/B/C × N=10/50/100 matrix against the S1 den override; tabulate against `s1-baseline.md`.
- [ ] **Step 2:** real-axon parity — eval the persist-claims demo + the axon `toplevel.drvPath` with `--override-input den path:<s1-worktree>`; string-compare to the pre-S1 value (capture both).
- [ ] **Step 3:** write `s1-result.md` (durable evidence; not committed in-repo).

---

### Task 5: clean-diff prep + tracker + memory + handoff

**Goal:** Leave S1 as a clean, mergeable den diff with a self-contained commit, update the durable tracker + the hola memory, and stage the S2 plan.

**Files:**
- Modify (papers): this plan's `.md.tasks.json`; `RESUME-fleet-architecture.md` (mark S1 done); memory `project_hola.md` CURRENT STATE tail.
- den: ensure `feat/s1-per-sid-hostconfig` is a focused 2-3-file diff rebaseable onto `denful/den` main.

**Acceptance Criteria:**
- [ ] `git -C <den-worktree> diff fix/broadcast-home-pool-to-host` touches only `resolve.nix`, `assemble-pipes.nix`, `spawn-node.nix`, and the regression fixture — no incidental churn.
- [ ] Commit message explains the footgun + the set/fn split (normal prose, no co-authored-by).
- [ ] `.md.tasks.json` Tasks 0-5 = completed; `s1-baseline.md` + `s1-result.md` committed to the papers archive.
- [ ] `project_hola.md` CURRENT STATE updated **in place** (S1 done; S2 next) per the hub's tail-replace hygiene; NOT a new appended paragraph.
- [ ] Decision recorded: open a `denful/den` PR for S1 now, or hold on the branch pending den-hoag (the §8a D5 open question) — surface to the user.

**Verify:** `git -C <den-worktree> diff --stat`; `cat` the updated tasks.json; memory tail reflects S1 complete.

**Steps:**
- [ ] **Step 1:** confirm the diff is clean + focused; reword the commit if it accreted WIP.
- [ ] **Step 2:** commit the papers evidence (`s1-baseline.md`, `s1-result.md`) + update `RESUME-fleet-architecture.md` build-order item 2 (S1 portion done).
- [ ] **Step 3:** update `.md.tasks.json` + `project_hola.md` CURRENT STATE tail (in place).
- [ ] **Step 4:** surface the den-PR-vs-hold decision to the user; then proceed to the S2 plan (cone-expander `pipe.reads` + the unscoped-collectAll lint).
