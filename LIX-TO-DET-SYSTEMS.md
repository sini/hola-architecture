# LIX → CppNix → Determinate — phased migration for nix-config

> Paste into a fresh agent session to migrate `~/Documents/repos/sini/nix-config`
> off Lix in **two phases**: **(1) Lix → vanilla CppNix** (substrate parity +
> clean baselines), then **(2) CppNix → Determinate Nix** (the parallel-eval perf
> trial, measured against the Phase-1 baseline). Dated 2026-06-24. File:line refs
> verified at that revision. Repo is a dendritic/den fleet on a **colmena fork**;
> `nix-config` is a **public** GitHub repo — obey §C conventions.

## 0. Why phased (don't relitigate)

`nixos-rebuild`/eval on `cortex` is slow (~33–50s). Profiling settled the cause: of
the ~33.5s wall on `cortex`'s `toplevel.drvPath`, **~21s (63%) single-threaded eval,
~10s (30%) I/O, ~2s (6%) GC.** GC tuning was tested and moves wall <7%. **The wall is
single-threaded-eval-bound; the 9950X3D runs 31 idle cores.** Only **Determinate**
ships a parallel evaluator (`eval-cores`) — neither Lix nor upstream CppNix has one.

But we split the move, because the two reasons are different:

- **Phase 1 (Lix → CppNix) is about *parity*, not speed.** CppNix is the evaluator
  the majority of nixpkgs users run, and the upstream convergence point Determinate
  targets. Running it (a) aligns the fleet — and hola's parity-harness CI — with the
  reference evaluator, closing the Lix-only divergence blind spot; (b) is the
  *simplest* exit (delete Lix wiring; `nix.package` falls back to the NixOS default —
  no vendor); (c) keeps zero telemetry. It does **not** change the 33.5s.
- **Phase 2 (CppNix → Determinate) is the speed trial.** Parallel eval + lazy-trees,
  measured against the *Phase-1 CppNix baseline* (a clean apples-to-apples number),
  with a vendor + telemetry cost weighed only if the win is real.

**Establish the CppNix baseline first, then test whether Determinate beats it.**

## Blast radius (both phases): 10 hosts

`roles.default` → `core.nix` aspect → `core/nix/lix.nix` applies to **9 NixOS + 1
darwin**: `cortex`, `cortex-cuda` (microvm guest on cortex), `axon-01/02/03`,
`blade`, `uplink`, `bitstream` (x86_64-linux), `patch` (aarch64-darwin).
**`slab` (nix-on-droid) is EXCLUDED** — it uses `core.nix-on-droid-base`, not
`roles.default`. Leave `slab` alone. Canary = **cortex first**, both phases.

---

# PHASE 1 — Lix → vanilla CppNix

**Goal:** drop Lix entirely; system Nix reverts to upstream CppNix (nixpkgs default).
Establish the byte-identical correctness gate + the eval baseline. No vendor, no
telemetry, no perf change expected.

## 1.1 Current Lix wiring (remove/replace)

Inputs live in a **generated flake** — edit `flake-file.nix`, not the root
`flake.nix` (§C).

| Site | What it does |
|---|---|
| `flake.nix:102` + `modules/flake-parts/flake-file.nix:100-102` | `flake-compat.url = "github:lix-project/flake-compat"` |
| `flake.nix:155-158` + `flake-file.nix:174-177` | `lix` input (`github:lix-project/lix`, `flake = false`) |
| `flake.nix:159-165` + `flake-file.nix:179-185` | `lix-module` input (`git+https://git@git.lix.systems/lix-project/nixos-module`) |
| `modules/flake-parts/pkgs.nix:22-23` | `lix-module.overlays.default` applied **first** (provides `lixPackageSets`) |
| `modules/den/aspects/core/nix/lix.nix:1-12` | imports `lix-module.nixosModules.default` (Linux) + `darwinModules.default` (macOS) — **sets `nix.package = pkgs.lix`** |
| `modules/den/aspects/core/nix/nix.nix:1-112` | fleet-wide `nix.settings`; **no explicit `nix.package`** — Lix sets it via the module above |
| `modules/den/batteries/colmena.nix:119` | `nix-eval-jobs = pkgs.lixPackageSets.stable.nix-eval-jobs` |
| `flake.lock:660,664,1945,1949` | locked `git.lix.systems` URLs |

## 1.2 Steps

1. **Inputs** — in `modules/flake-parts/flake-file.nix`: remove `lix`, `lix-module`,
   and `flake-compat` (the lix-project fork). If `flake-compat` is still referenced,
   repoint to `github:edolstra/flake-compat`; else drop it. Regenerate root
   `flake.nix` (`nix run .#write-flake` / `CLAUDE.md`).
2. **Swap aspect** — rewrite/retire `modules/den/aspects/core/nix/lix.nix`: drop the
   `lix-module` imports. With nothing setting `nix.package`, it falls back to the
   NixOS default (upstream CppNix). **Decide:** leave the default, or pin explicitly
   `nix.package = pkgs.nixVersions.latest;` in `core/nix/nix.nix` (recommended — makes
   the version legible and bumpable). Consider deleting the aspect file and dropping
   it from the `core.nix` importer.
3. **Overlay** — `pkgs.nix:22-23`: remove the `lix-module.overlays.default` line.
   `lixPackageSets` disappears → fix consumers (next step).
4. **nix-eval-jobs** — `colmena.nix:119`: replace
   `pkgs.lixPackageSets.stable.nix-eval-jobs` with `pkgs.nix-eval-jobs` (nixpkgs).
   Verify colmena still evaluates.
5. **Lock** — run the repo wrapper `nix-flake-update` (wraps `nix flake update` with a
   GitHub token; `-e <input>` excludes one). Confirm `git.lix.systems` URLs are gone
   from `flake.lock`. This bumps `flake.lock` ⇒ the `nixidy-sync` pre-commit hook
   fires (§C) — refresh the devshell first.

**No `nix.package` collision in Phase 1** — you're *removing* a setter, not adding
one. (The collision is a Phase-2 concern, and Phase 1 pre-empties it.)

## 1.3 Validation + baseline (canary = cortex)

**A. Correctness gate (byte-identical .drv):** same nixpkgs ⇒ the toplevel `.drv`
must be **identical** Lix-vs-CppNix. Capture *before* removing Lix, then after:
```
# the Lix baseline you already have:
nix eval --no-eval-cache --raw .#nixosConfigurations.cortex.config.system.build.toplevel.drvPath
# after the Phase-1 changes, eval the same attr; string-compare (or nix-diff).
```
A mismatch means dropping Lix changed evaluated semantics — investigate before apply.
(Expectation: identical. Lix and CppNix share the same nixpkgs eval for this.)

**B. The CppNix eval baseline (the point of Phase 1):** measure wall/copies/heap on
CppNix so Phase 2 has an apples-to-apples reference:
```
cd ~/Documents/repos/sini/nix-config
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/cppnix-cortex.json \
  time nix eval --no-eval-cache --raw .#nixosConfigurations.cortex.config.system.build.toplevel.drvPath >/dev/null
```
Record next to the **Lix baseline: ~33.5s wall / 36.9s cpuTime / 5.9 GB heap /
235.77M copies**. Expect ≈ Lix (both single-threaded; Lix is marginally leaner on RAM,
CppNix may be marginally faster on rebuild since Lix took a 3% eval-time regression
for its memory wins). Single-digit-% either way — Phase 1 is not a speed move.

**C. Apply the canary (cache-then-colmena — the repo's path):** cortex is the local
host. CppNix's `nix` is in your default substituters, so no extra cache flags:
```
nix-flake-build cortex      # nom build --no-link on cortex toplevel; surfaces eval errors, caches the closure
colmena apply-local --sudo  # activates the already-built store path
```

**D. Confirm CppNix is live:**
```
nix --version   # plain 'nix (Nix) 2.3x', NOT 'Lix'
systemctl cat nix-daemon.service | grep ExecStart   # standard nix-daemon (no determinate-nixd)
```

**E. Fleet rollout** (only after cortex validates): host-by-host, prior generations
bootable. k8s nodes (`axon-*`, `blade`, `uplink`, `bitstream`) last, one at a time.

**Point hola's CI/dev at CppNix too** — the mission payoff: the parity harness now
proves byte-identical on the evaluator users actually run.

---

# PHASE 2 — CppNix → Determinate Nix (perf trial)

**Goal:** trial Determinate's parallel evaluator against the Phase-1 CppNix baseline.
Canary cortex; keep it only if the measured win justifies the vendor + telemetry cost.

## 2.1 Integration (verified from source)

Add input (pin major `/3`; **do NOT** add a nixpkgs `follows` — causes FlakeHub Cache
misses):
```nix
determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/3";
```
Import the module in `core/nix/` (NixOS confirmed; **verify the darwin attr** for
`patch`):
```nix
imports = [ inputs.determinate.nixosModules.default ];
# patch (darwin): verify inputs.determinate.darwinModules.default exists; else Linux-only.
```
What `determinate.nixosModules.default` does (`modules/nixos.nix`, `determinate.enable`
defaults true): sets `nix.package = inputs.nix.packages.<system>.default` (Determinate's
Nix — where `eval-cores`/`lazy-trees` live); rewrites `systemd.services.nix-daemon`
ExecStart → `determinate-nixd … daemon` + socket; redirects `/etc/nix/nix.conf` →
`nix.custom.conf` (route settings through `nix.settings`, never hand-edit); adds
`determinate-nixd` to systemPackages. Does **not** set substituters/keys/`eval-cores`/
`lazy-trees` — those are yours.

### Settings (in `core/nix/nix.nix` fleet-wide `nix.settings`)
```nix
nix.settings = {
  eval-cores = 0;     # all cores. Determinate default 1 (single-threaded). NON-experimental.
  lazy-trees = true;  # store-copy sources only when used. Default false. NON-experimental (≥3.21).
  extra-substituters = [ "https://install.determinate.systems" ];
  extra-trusted-public-keys = [ "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM=" ];
  # Add "parallel-eval" to experimental-features ONLY for builtins.parallel (preview, skip).
};
```

### Telemetry (on by default — disable)
```nix
environment.variables.DETSYS_IDS_TELEMETRY = "disabled";
environment.etc."determinate/config.json".text = ''{ "telemetry": { "sentry": { "endpoint": null } } }'';
```
Caveat: also disables Determinate's feature-rollout tooling. Acceptable.

## 2.2 The one hard blocker (now pre-empted by Phase 1)

Determinate's module sets `nix.package` at default priority. **If lix-module were
still imported, both would set it → "option `nix.package` is defined multiple times".**
Phase 1 already removed lix-module, so this is clear — but if you skipped Phase 1,
remove lix-module first. Also `grep -rn 'nix.package' modules/` to confirm nothing
else sets it. Catch with `nix-flake-build cortex` before any apply.

## 2.3 Validation (canary = cortex)

**A. Build dry-run:** `nix-flake-build cortex` — must eval+build clean (surfaces any
`nix.package` collision; caches the closure for colmena).

**B. Correctness gate (byte-identical .drv):** Determinate's toplevel `.drv` must
equal the **Phase-1 CppNix** `.drv` (same nixpkgs ⇒ same derivation). A mismatch =
the evaluator changed semantics — investigate before fleet.
```
# Phase-1 CppNix drvPath (recorded) vs Determinate:
nix eval --no-eval-cache --raw .#nixosConfigurations.cortex.config.system.build.toplevel.drvPath
```

**C. Apply the canary (cache-then-colmena):** the Determinate Nix binary isn't in your
default substituters yet, so pass the cache as `=`-long-flags (**`nix-flake-build`
parses `--flag=value` as one token; the `--option name val` three-token form is
mis-read as hostnames**):
```
nix-flake-build cortex \
  --extra-substituters=https://install.determinate.systems \
  --extra-trusted-public-keys='cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM='
colmena apply-local --sudo
```
Once Determinate is the default daemon, drop the flags:
`nix-flake-build cortex && colmena apply-local --sudo`.

**D. Confirm Determinate is live:**
```
nix --version                                       # 'Determinate Nix 3.x'
systemctl cat nix-daemon.service | grep ExecStart   # determinate-nixd … daemon
nix config show eval-cores                          # => 0
nix config show lazy-trees                            # => true
readlink -f /etc/nix/nix.conf                        # determinate-managed (nix.custom.conf)
echo "$DETSYS_IDS_TELEMETRY"                          # disabled
```

**E. The perf A/B (the whole point):** compare against **both** the Phase-1 CppNix
baseline and the Lix ~33.5s:
```
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/det-cortex.json \
  time nix eval --no-eval-cache --raw .#nixosConfigurations.cortex.config.system.build.toplevel.drvPath >/dev/null
```
Expect a meaningful wall drop from parallel eval. **Updated expectation (better than
my earlier guess):** cortex's eval has large *independent* subtrees — 3 home-manager
users (~46% of heap) + the cortex-cuda guest (~8%) — which `eval-cores` parallelizes
well, so the single-host win may exceed the ~2–3× I first estimated. Also time
`nix flake check` (multi-system axis, expect ~3–4×). **These numbers decide fleet
rollout.**

**F. lazy-trees audit:** `lazy-trees=true` makes `src = ./.` double-copy + warn.
`grep -rn 'src = ./\.' modules/ pkgs/` → rewrite to
`src = builtins.path { path = ./.; name = "source"; };` or `src = self;`.

**G. Fleet rollout:** only after cortex validates. Remote host: cache then deploy —
`nix-flake-build <host> --extra-substituters=… --extra-trusted-public-keys=…` then
`colmena apply --on <host>` (drop flags once Determinate is fleet default). k8s nodes
last, one at a time.

---

# Shared

## A. Orthogonal pure-config eval win (independent of both phases)

The 33.5s is **~46% home-manager** (3 users `shuo`/`sini`/`will`, 2.7 GB, 15s),
**~8% the cortex-cuda guest**, **~44% base OS**, and **only ~1.6% stylix**. The HM
cost is amplified by `useGlobalPkgs = false` + **per-user overlays**
(`nix-vscode-extensions` → `pkgs.vscode-marketplace.*`): each user instantiates its
own nixpkgs and re-applies the overlays. **Fix (pure config, no evaluator change):**
hoist those overlays into the system overlay chain (`pkgs.nix`), then set
`home-manager.useGlobalPkgs = true` → one shared overlaid `pkgs` across all users.
Gate byte-identical via the same `drvPath` check. Reclaims a chunk of the 108M copies
regardless of which Nix you run. (The residual per-user *module* re-evaluation is the
cross-scope eval-sharing problem — a separate hola/zen track.)

## B. Rollback

- **Declarative:** revert the aspect (re-add lix-module, or drop the determinate
  module) → `nix-flake-build <host>` then `colmena apply-local --sudo` (local) /
  `colmena apply --on <host>` (remote). Atomic per generation.
- **Fast:** `sudo nixos-rebuild switch --rollback` or boot the prior generation
  (carries old daemon + `nix.package`; independent of colmena).
- **Sequencing:** canary cortex, prior generation bootable, validate, then promote.

## C. Repo conventions (must obey)

- **Generated flake:** edit `modules/flake-parts/flake-file.nix`, regenerate
  (`nix run .#write-flake`). Never hand-edit root `flake.nix`.
- **Format:** `nix fmt` (treefmt-nix / nixfmt). NOT bare `treefmt`. CI `fmt.yml` enforces.
- **Linear history:** `main` rejects merge commits — rebase / ff-only, never `--no-ff`.
- **Public repo:** no IPs/domains/ports/host-counts in commits or PR bodies (hosts
  carry real IPs, e.g. cortex `10.9.2.1/16`). Generalize.
- **Commits:** no `Co-Authored-By`, no "Generated with…" footers; stage files by name
  (never `git add -A`/`.`).
- **`nixidy-sync` hook** (`nixidy.nix:223`) regenerates k8s manifests on `flake.lock` /
  k8s-aspect changes. **Gotcha (line 200):** a stale direnv shell syncs old manifests →
  commit fails. Refresh the devshell (`nix develop -c true` / `direnv reload`) before
  committing. Both phases bump `flake.lock` → expect it.
- **CI gate:** `.github/workflows/{fmt,update-flakes}.yml`. Green before merge.

## D. Open decisions

1. **Stop at Phase 1?** If the parity/governance reasons are the whole motivation and
   eval speed is tolerable, CppNix may be the destination — Phase 2 is optional.
2. **Darwin (`patch`):** migrate (either phase) only if the relevant module exists;
   else Linux-only.
3. **FlakeHub Cache (Phase 2):** the public key only *verifies*; using it for your
   artifacts needs `determinate-nixd login`. Default: don't.
4. **nixpkgs skew (Phase 2):** keep the fleet's `nixpkgs` separate; don't make
   determinate `follows` it.

## Risk summary

Phase 1 — low: it's mostly *deletion*; only real risk is a non-identical drvPath
(investigate) or a stray `lixPackageSets` consumer. Phase 2 — high: `nix.package`
collision if lix-module lingers (Phase 1 pre-empts); medium: lazy-trees `./.`
double-copy (§2.3F), default telemetry, FlakeHub/nixpkgs-weekly skew, **lazy-trees
store-path determinism is upstream-unresolved** (PR #13225) — relevant to your
byte-identical ethos; low: `builtins.parallel` instability (skip it).

---

*Companion: `project_hola` memory (perf re-pivot + measured cortex decomposition).
Phase 1 = substrate parity with the majority's evaluator + clean baseline; Phase 2 =
the parallel-eval trial. The cross-host/cross-scope eval-sharing lever and the parity
harness are separate hola tracks.*
