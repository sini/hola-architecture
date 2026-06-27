# RESUME PROMPT — synthetic-fleet harness (paste into a fresh session)

You are resuming the **synthetic-scale fleet + observability harness** (step 2.0 of the
open-emit affordability program — part of the hola fleet-eval-sharing work). The spec and plan
are written, reviewed, and committed; harness Tasks 0–3a are built and verified; **Task 3b is
next.**

## Read first (context, in order)
1. Memory `project_hola` (dense record) + `~/Documents/papers/hola-architecture/RESUME-fleet-architecture.md` (the program this 2.0 work sits inside — open emit = the value).
2. **Spec:** `~/Documents/papers/hola-architecture/specs/2026-06-26-synthetic-fleet-harness-design.md` (authoritative; §8 has the full review fold-in).
3. **Plan + tracker:** `~/Documents/papers/hola-architecture/plans/2026-06-26-synthetic-fleet-harness.md` and its `.md.tasks.json` (task status — Tasks 0,1,2,3a = completed).
4. Step-1 evidence (the demo this builds on): `analysis/experiments/fleet-open-emit/` (real-axon OPEN cross-host emit, measured: M1/M2/M3 pass).

## The repo / worktree
- nix-config worktree: `~/Documents/repos/sini/nix-config/.worktrees/persist-claims-open-emit`, branch `demo/persist-claims-open-emit` (**throwaway, never merged**), HEAD `50826f63`.
- den is **UNCHANGED**; the harness only adds `modules/den/synth/**` + `synth-measure/**`. Durable artifacts = the papers archive (the branch is captured as patches, not merged).

## ⚠️ CRITICAL WORKAROUND (read before any eval)
Evaluating the synth flake **as user `sini` via the nix-daemon HANGS** (5 min+, unresolved
nix-env bug — NOT a harness/den bug). **Use the root/direct-store workaround for ALL harness
evals** (3 s, results are user-independent so measurements stay valid):
```bash
FLAGS='--extra-experimental-features "nix-command flakes pipe-operators" --accept-flake-config'
sudo -n env NIX_REMOTE= nix eval $FLAGS --apply '<f>' '.#<attr>'
```
The hang is documented for a SEPARATE focused session in
`analysis/sini-daemon-eval-hang-DEBUG.md` (top lead: client=CppNix 2.34.7 vs **daemon=Lix**
protocol mismatch — a 30-second check). **Do NOT re-debug the daemon hang here; just use the
workaround and proceed with the harness.**

## Done (Tasks 0–3a), all committed on the branch
- **0 factory** (`modules/den/synth/{options,factory,enable}.nix`): N synth host entities, per-index identity axis, `classKey = (sorted includes, channel, system)`; `synthFleet.enable` (committed `enable.nix`, NOT `_enable.nix` — import-tree excludes `/_`). Debug surfaces: `flake.den-debug.{synthHosts,classKey,synthFacter,synthSecrets}`.
- **1 facter** (`facter.nix`, `facter-base.json`, `synth-measure/gen-keys.sh` → committed `keys/synth-keys.json`, 128 recipients): `synthFleet.facterRegime` (fleet-level shared|varied); facter IS eval-forced → `facts` overridden via `builtins.toFile` (no IFD); device_id decoupled from facter disks.
- **2 secrets** (`secrets.nix`, `keys/synth-master.pub`, `synth-measure/00-rekey.sh`): agenix `rekey --dummy`; per-host recipient = facter pubkey; **per-host ciphertext variance preserved** (no 8b fidelity caveat); real-fleet byte-identical (verified). Private master key dropped.
- **3a skeleton** (`skeleton.nix`): realistic-axon default `classes` (base + superclass via `media-scratch` + server/agent as distinct k3s includes, ≥2 channels = nixos-unstable + nixpkgs-master), synth environment + cluster + bgp-hub, `heavyClosedAspects` toggle. **`core.nix.remote-build-client` is commented out of `roles.default`** (its dead-SSH-builder machinery; unrelated to the daemon hang but kept off). Verified via workaround (3 s): 10 hosts generate, full-axon config structurally resolves no-throw.

## NEXT: Task 3b — criterion 1a (config fixpoint forces without throwing at scale)
Goal: for N=10→50→100, every synth host's config fixpoint forces **without throwing**, where
"force" = `deepSeq` of `config.assertions` + the in-cone subtrees `{systemd,networking,disko,age}`
**minus derivation-building leaves** (spec §4.1a). File: `synth-measure/1a-nothrow.sh` (uses the
root workaround). State the coverage ceiling (1a green = throw-free in the forced cone, not
whole-config). Run heavy-off then heavy-on. This is the eval-feasibility/debug task; expected
landmines (now mostly de-risked since structure already resolves): bgp-hub at scale, k3s,
mesh, secrets coherence. Then **Task 4** (open-emit variants + collect modes + S1 global-flag
trigger + cycle-rejection test = Phase-1 checkpoint), then **Phase 2 (Tasks 5–11)** = the
observability layer (driver, differential perf, sentinels, share-ratio incl. 8b two-regime
facter differential, canonicalized-core parity oracle, provenance, baseline N=100 report).

## Execution model + conventions
- Use **subagent-driven-development** (coordinator dispatches one implementer subagent per task + spec/quality review), OR continue directly for the measurement scripts. Update `.tasks.json` status as tasks complete (it's the durable tracker; native CC tasks are NOT used — the pre-commit-check-tasks hook blocks commits when native tasks are incomplete).
- `git add` new files before `nix eval` (flakes ignore untracked). Commit in the worktree with `PREK_ALLOW_NO_CONFIG=1` (fresh worktree has no `.pre-commit-config.yaml`). **Do NOT run `git stash`** in the worktree (the user's stashes live there). Every measured eval: `--option eval-cache false` + the root workaround.
- Honor the feedback memories: caveman-lite to subagents, opus for non-mechanical work, write specs/evidence to papers (never commit docs in-repo), explicit git staging by name.

## Broader session context (already done — don't redo)
Architecture spec committed (papers `279d4cd`); real-axon open-emit demo built + measured (Task 1 of the fleet build order, evidence `7ebf82f`); the full 2.0 spec + plan through 3+2 review iterations. This RESUME covers continuing the harness EXECUTION from Task 3b.
