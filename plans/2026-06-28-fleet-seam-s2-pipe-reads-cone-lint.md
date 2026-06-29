# Fleet Seam S2 — `pipe.reads` cone-expander + unscoped-collectAll lint Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers-extended-cc:subagent-driven-development (if subagents available) or superpowers-extended-cc:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `pipe.reads [paths]` combinator — an open (`{ config, … }`) cross-host emit declares the config-field cone it reads — resolved against a **cone-restricted view** of the peer config (S1's `hostConfigFor`) where undeclared reads throw; plus a **lint** that rejects a config-dependent emit collected via `collect`/`collectAll` *without* a `reads` declaration (the unscoped fleet-wide blow-up shape). "DECLARE the boundary, not DISCOVER it," extended to the open axis at field granularity.

**Architecture:** S1 made `hostConfigFor sid` a lazy per-sid full peer config. S2 layers a *declared cone* on top: `pipe.reads ["services.k3s.token"]` annotates an open emit; at resolution the emit sees a peer config **restricted to the declared paths** (everything else throws "undeclared read") — enforcing that the declaration is honest, so the cone is sound for the downstream uses (the affected-set, class-share, blast-radius). **Honest value (measured grounding, do not over-sell):** Nix laziness *already* scopes the runtime read to the fields touched (step-1: an open read forced 8.3% of toplevel copies, 91.7% derivation-construction avoided), and the cone is **base-dominated** (the module-fixpoint base is memoized across same-system peers). So `pipe.reads`'s payoff is **declarative enforcement + the lint**, NOT a large new runtime saving. The lint is the part that earns its keep (it forbids the one real blow-up: unscoped `collectAll` + config-dep, the synth `globalTrigger` shape). This is spec §8a **S2**.

**Tech Stack:** den fx (`nix/lib/policy-effects.nix` pipe combinators; `nix/lib/aspects/fx/assemble-pipes.nix` `resolveEntry`/stage interpreters — S1-modified); den CI (`just ci`); the synthetic-fleet harness (`globalTrigger`/`synthOpenTrigger` collectAll fixture = the lint bite-target) + real axon for byte-identity.

---

## Context the implementer needs (read before Task 0)

**Where things are (den worktree, post-S1 `b3449c8b`):**
- `nix/lib/policy-effects.nix:296-350` — the `pipe` attrset. Stages are tagged records: `collect = pred: { __pipeStage = "collect"; fn = pred; }`, `collectAll = pred: { … "collectAll"; fn = pred; }`, `broadcast`, `filter`, `transform`, `expose`, etc. **`pipe.reads` is a NEW stage here.**
- `nix/lib/aspects/fx/assemble-pipes.nix` — the stage interpreters consume `__pipeStage` records and resolve collected/broadcast config-dependent emits via `resolveEntry` (S1: `resolveEntry` defers on `hostConfigScopeIds == {}`, else resolves via `producerConfigFor` which reads `hostConfigFor sid`). **This is where a `reads` annotation must restrict the config view, and where the lint fires.** The implementer MUST trace how a `collect`/`collectAll` stage's collected entries reach `resolveEntry` and how a sibling `reads` stage in the same `pipe.from [...]` chain is carried alongside.
- `isConfigDependent = val: builtins.isFunction val && (builtins.functionArgs val) ? config` (resolve.nix:392 / mirrored in assemble-pipes) — the open-emit predicate; the lint keys on it.

**The API surface (spec §8a S2, Form C):** a policy declares the cone next to the collect:
```nix
pipe.from "persist-claims" [
  (pipe.reads [ "users.users" "users.groups" ])   # S2: the declared config cone
  (pipe.collect ({ host, ... }: host.name == "backup-host"))
]
```
`pipe.reads [paths]` = `{ __pipeStage = "reads"; paths = [ ... ]; }` (paths are dotted-string attr-paths into the peer `config`).

**The cone-restriction mechanism (resolve a config-dep emit against the declared cone):** given S1's `hostConfigFor sid` (full lazy peer config) and the declared `paths`, build a **restricted view**:
```nix
coneView = cfg: paths:
  # an attrset exposing ONLY the declared paths from cfg; any access outside the
  # cone throws "den: pipe.reads: undeclared config read at <path>". Build by
  # folding `paths` into a nested attrset via lib.attrByPath/setAttrByPath, with a
  # throwing fallback so the emit cannot silently read beyond its declaration.
```
The emit resolves against `coneView (hostConfigFor sid) declaredPaths` instead of the full `hostConfigFor sid`. **Honesty:** because Nix is lazy, the full-config resolution already only forces the read fields — so `coneView`'s job is **enforcement** (undeclared reads fail loud ⇒ the declaration is trustworthy), not a runtime cut. Keep this framing in the code comments; do NOT claim a copies saving the measurement doesn't support.

**The lint (the keeper):** "always-true predicate" is undetectable in Nix (a predicate is an opaque function). So the lint is **structural**: a `collect`/`collectAll` stage whose collected emit `isConfigDependent`, in a `pipe.from` chain that has **no `reads` stage**, is rejected:
```
den: pipe.<collect|collectAll>: open (config-dependent) cross-host emit "<pipe>" must declare its
read cone with `pipe.reads [ … ]` (the unscoped form forces every peer's full config — the fleet
blow-up). Add a pipe.reads stage naming the config fields it reads.
```
This forces the declaration; `collectAll` + config-dep + no-reads = the synth `globalTrigger` shape = the bite-target that MUST be rejected post-S2. (A `collect` with a scoped predicate + config-dep also requires `reads` — same rule; scope bounds *which* peers, `reads` bounds *which fields*.)

**Branch base:** S2 builds on S1 (`hostConfigFor`). Branch the S2 worktree off `feat/s1-per-sid-hostconfig` (`b3449c8b`), so S2 = S1+S2 stacked. Validate with `--override-input den path:<s2-worktree>`. The S2 diff stays focused (policy-effects.nix + assemble-pipes.nix + a fixture), rebaseable after S1.

**Conventions:** explicit `git add` by name; `just fmt` (or `nixfmt` direct if `nix fmt` hangs); den CI `just ci`; no Co-Authored-By; evidence → papers; worktrees under `.worktrees/`; caveman-lite to subagents; opus.

---

### Task 0: S2 den worktree (off S1) + override + lint bite-target confirmation

**Goal:** A den worktree stacked on S1, wired into the harness; confirm the synth `globalTrigger`/`synthOpenTrigger` collectAll fixture currently RESOLVES (pre-S2) — it is the unscoped open emit the S2 lint will reject.

**Files:**
- Create: den worktree `~/Documents/repos/den/.worktrees/s2-pipe-reads` (branch `feat/s2-pipe-reads` off `feat/s1-per-sid-hostconfig`).
- Read: `nix/lib/policy-effects.nix:294-350`; the assemble-pipes stage interpreters + `resolveEntry`; the harness `modules/den/synth/{open-emits,collect-policies}.nix` (the `synthOpenTrigger` collectAll = the bite-target).

**Acceptance Criteria:**
- [ ] den worktree on `feat/s2-pipe-reads` off `b3449c8b`; clean.
- [ ] `--override-input den path:<s2-worktree>` evaluates the synth harness identically to the S1 worktree (pre-S2, no behavior change yet).
- [ ] Confirmed: with `globalTrigger=true`, `synthOpenTrigger` (config-dep, `collectAll (_:true)`) currently RESOLVES (this is the shape S2 must reject). Recorded.

**Verify:** `synth_eval_attr` of the trigger surface with `globalTrigger=true` resolves under the S2 worktree (pre-change); classKey byte-identical to S1.

**Steps:**
- [ ] **Step 1:** `git -C ~/Documents/repos/den worktree add .worktrees/s2-pipe-reads -b feat/s2-pipe-reads feat/s1-per-sid-hostconfig`.
- [ ] **Step 2:** sanity — classKey N=10 byte-identical S1-worktree vs S2-worktree (no change yet); confirm `globalTrigger=true` trigger resolves.

---

### Task 1: `pipe.reads [paths]` stage + carry the cone to resolution

**Goal:** Add the `reads` combinator and thread the declared paths from the `pipe.from` chain to the point where the collected config-dependent emit resolves.

**Files:**
- Modify: `nix/lib/policy-effects.nix` (add `reads` to the `pipe` attrset).
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (collect/collectAll/broadcast stage processing — extract a sibling `reads` stage's `paths` and carry them to `resolveEntry`/`producerConfigs`).

**Acceptance Criteria:**
- [ ] `pipe.reads = paths: { __pipeStage = "reads"; paths = <list of dotted-string paths>; }` added (mirrors the other stage builders; validate `paths` is a list of strings).
- [ ] The stage interpreter for a `pipe.from` chain extracts the `reads` stage (if present) and makes its `paths` available where the collected config-dependent emit is resolved (alongside the collect predicate). A chain with no `reads` stage carries `null`/absent (→ lint in Task 3, or full config if pre-existing closed path).
- [ ] No behavior change yet for emits without `reads` (Task 2 adds restriction; Task 3 adds the lint). den evaluates.

**Verify:** a `pipe.from [ (pipe.reads [...]) (pipe.collect …) ]` policy parses + the paths reach resolution (add a debug assertion or trace); den CI still green.

**Steps:**
- [ ] **Step 1:** add `reads` to `policy-effects.nix` `pipe` attrset.
- [ ] **Step 2:** trace the `pipe.from` stage list through assemble-pipes; in the collect/collectAll/broadcast handler, find the sibling `reads` stage (`builtins.filter (s: s.__pipeStage or null == "reads")`) and thread its `paths` to the config-dep resolution site.

---

### Task 2: cone-restriction — resolve config-dep emits against the declared cone

**Goal:** When a config-dependent emit has a `reads` declaration, resolve it against a peer-config view restricted to the declared paths; an undeclared read throws.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (`producerConfigs`/`resolveEntry` — build `coneView` from `hostConfigFor sid` + `paths`).

**Acceptance Criteria:**
- [ ] `coneView cfg paths` = an attrset exposing only the declared paths of `cfg`; access outside the cone throws `den: pipe.reads: undeclared config read at "<path>"` (build by folding `paths` via `lib.setAttrByPath (lib.splitString ".")` + `lib.attrByPath` over `cfg`; the top-level + intermediate keys not in any declared path throw on access).
- [ ] A `reads`-declared config-dep emit resolves against `coneView (hostConfigFor sid) paths` (NOT the full `hostConfigFor sid`).
- [ ] Reading a declared path returns the real peer value (byte-identical to the unrestricted read — laziness already scoped it; the cone only *bounds*, doesn't *change*, the declared values).
- [ ] An emit that reads a path OUTSIDE its declaration throws the undeclared-read error (a teeth test in Task 4).
- [ ] Code comments state the honest framing: the cone is ENFORCEMENT (undeclared reads fail loud), not a runtime copies cut (laziness already scopes it; base-dominated).

**Verify:** a `reads`-declared emit resolves to the same value as the unrestricted version (byte-identical); an out-of-cone read throws.

**Steps:**
- [ ] **Step 1:** implement `coneView` — SIMPLER than a throwing proxy: build an attrset containing **only** the declared paths' real values; undeclared access then throws Nix's own "attribute … missing" naturally (no custom fallback needed). E.g. `coneView = cfg: paths: lib.foldl' (acc: p: let parts = lib.splitString "." p; in lib.recursiveUpdate acc (lib.setAttrByPath parts (lib.getAttrFromPath parts cfg))) { } paths;` (`lib.getAttrFromPath` already throws a clear error if a *declared* path is absent on the peer). The result exposes exactly the cone; `cfg.<undeclared>` is simply not present ⇒ throws on read. Optionally wrap the missing-attr message to mention `pipe.reads` for a nicer author error, but the natural throw is sufficient enforcement.
- [ ] **Step 2:** in `resolveEntry`/`producerConfigs`, when a `reads` declaration is present for the emit, substitute `coneView (hostConfigFor sid) paths` for the full peer config in the thunk args.

---

### Task 3: the lint — config-dep collected emit must declare `reads`

**Goal:** Reject a config-dependent emit collected via `collect`/`collectAll` in a chain with no `reads` stage — the unscoped open-emit blow-up shape.

**Files:**
- Modify: `nix/lib/aspects/fx/assemble-pipes.nix` (or wherever pipe chains are validated — the collect/collectAll handler).

**Acceptance Criteria:**
- [ ] A `pipe.from` chain with a `collect`/`collectAll` stage whose collected emit `isConfigDependent`, and NO `reads` stage, throws the lint error (message names the pipe + tells the author to add `pipe.reads [ … ]`).
- [ ] A chain WITH a `reads` stage passes (the cone is declared).
- [ ] A purely CLOSED (non-config-dep) collected emit is unaffected (no `reads` required — the lint keys on `isConfigDependent`).
- [ ] The lint fires at eval of the pipe resolution (fail-loud, not silent).

**Verify:** the synth `globalTrigger` fixture (`synthOpenTrigger` collectAll, config-dep, no reads) → **REJECTED** with the lint error; adding `pipe.reads` to it → passes.

**Steps:**
- [ ] **Step 1:** in the collect/collectAll handler, detect config-dep collected entries + the absence of a sibling `reads` stage → `throw` the lint.
- [ ] **Step 2:** verify closed emits + reads-declared emits are unaffected.

---

### Task 4: validation — lint fires, cone enforces, byte-identical

**Goal:** Prove S2 rejects the unscoped shape, enforces the cone, and changes nothing for real configs.

**Files:**
- Run-only: `just ci`; the synth harness (`globalTrigger` lint + a `reads`-annotated fixture); real axon byte-identity.
- Modify (harness, worktree): add a `reads`-annotated open-emit fixture to `modules/den/synth/{open-emits,collect-policies}.nix` (a scoped config-dep emit WITH `pipe.reads` — the positive path) + optionally make the `globalTrigger` fixture's expected outcome "lint-rejected."
- Create (papers): `analysis/experiments/synthetic-fleet/s2-result.md`.

**Acceptance Criteria:**
- [ ] **den CI green** — `just ci` same count as the S1 parent + any new S2 fixtures (closed emits + existing collect tests unaffected; if any den test uses a config-dep collectAll without reads, it must be updated to declare reads — record which).
- [ ] **Lint fires:** the synth `globalTrigger` (`synthOpenTrigger` collectAll, no reads) is REJECTED with the lint message; adding `pipe.reads` makes it resolve.
- [ ] **Cone enforces:** a `reads`-declared emit resolves byte-identically to the unrestricted read for declared paths; an out-of-cone read throws the undeclared-read error (teeth).
- [ ] **Real axon byte-identical:** `nixosConfigurations.{axon-02,axon-03}.…toplevel.drvPath` identical S1-worktree vs S2-worktree (S2 adds an unused-by-real-configs API ⇒ must be byte-identical). The pin-vs-override pattern from S1.
- [ ] Results → `s2-result.md`, with the honest framing (lint = the value; cone-restriction = enforcement, base-dominated, not a runtime saving).

**Verify:** `s2-result.md` shows lint-rejects-globalTrigger, cone-enforces (teeth), real-axon byte-identical, den CI green.

**Steps:**
- [ ] **Step 1:** add the `reads`-annotated synth fixture (positive path) + drive the lint on `globalTrigger`.
- [ ] **Step 2:** `just ci`; update any den test that relied on an undeclared config-dep collect (record).
- [ ] **Step 3:** real-axon byte-identity (S1 vs S2 override).
- [ ] **Step 4:** write `s2-result.md`.

---

### Task 5: clean-diff prep + tracker + memory + band wrap-up

**Goal:** Leave S2 as a focused den diff stacked on S1, update the durable tracker + memory, and mark the open-emit-affordability band complete.

**Files:**
- Modify (papers): this plan's `.md.tasks.json`; `RESUME-fleet-architecture.md` (item 2 — S2 done, band complete); memory `project_hola.md` CURRENT STATE tail (in place).
- den: `feat/s2-pipe-reads` = focused diff (policy-effects.nix + assemble-pipes.nix + fixture) on top of S1.

**Acceptance Criteria:**
- [ ] S2 diff vs `feat/s1-per-sid-hostconfig` touches only the pipe API + cone/lint + fixtures.
- [ ] Prose commit (no co-authored-by) explaining `pipe.reads` + the lint + the honest framing.
- [ ] `.md.tasks.json` Tasks 0-5 completed; `s2-result.md` committed to papers.
- [ ] `project_hola.md` CURRENT STATE tail updated in place: S2 done ⇒ **the open-emit-affordability band (Plane-2a + S1 + S2) is COMPLETE**; remaining = the den-hoag seam itself (§8a, separate program) + Plane-2b keystone (deferred).
- [ ] Band wrap-up surfaced to the user: all three scoped sub-projects done; what's left is explicitly deferred/den-hoag-gated.

**Verify:** `git -C <s2-worktree> diff --stat feat/s1-per-sid-hostconfig`; tasks.json all completed; memory tail = band complete.

**Steps:**
- [ ] **Step 1:** confirm focused diff; commit prose.
- [ ] **Step 2:** commit papers evidence + update RESUME + memory tail.
- [ ] **Step 3:** report band-complete to the user.
