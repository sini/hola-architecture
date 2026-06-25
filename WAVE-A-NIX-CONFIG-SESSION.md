# Wave A — nix-config cheap wins (CppNix Phase 1 + overlay C0)

> Session prompt for a fresh agent. Works in `~/Documents/repos/sini/nix-config`,
> **parallel to** the gen-rebuild v3 work (different repo, no conflict). Two
> independent, low-risk wins that gate on nothing and unblock the hola mission's
> substrate. Dated 2026-06-24. Pairs with `project_hola` memory + the full
> `LIX-TO-DET-SYSTEMS.md` (Phase 1 has every verified file:line).

## Why these two, now

Both gate on nothing and are mission-enabling:

- **A1 (Lix → CppNix)** aligns the dev/CI substrate with the evaluator the majority of
  nixpkgs users — and hola's parity gate — actually run. Proving the engine
  byte-identical on a *minority* evaluator (Lix) is a blind spot; CppNix removes it.
  Mostly *deletion*, low-risk.
- **A2 (overlay C0, `useGlobalPkgs=true`)** reclaims a chunk of cortex's ~33s eval
  (home-manager is ~46%, amplified by 3× per-user nixpkgs instantiation) **and**
  rehearses the **4-drvPath byte-identical gate** methodology the engine + cross-scope
  sharing (Phase 4.5) will reuse — a low-stakes dry run on a real config.

## CRITICAL: two SEPARATE commits/PRs, A1 first

A1's gate is **byte-identical** (Lix→CppNix must not change the build). A2 **may shift
drvPaths** (pkgs construction changes). Combined, A2's shift confounds A1's check.
**Land A1 → gate byte-identical → merge. THEN A2, separately.**

---

## A1 — Lix → vanilla CppNix

**Full verified steps:** `LIX-TO-DET-SYSTEMS.md` **Phase 1**. Summary:
- Remove `lix` / `lix-module` / the lix-project `flake-compat` inputs (edit
  `modules/flake-parts/flake-file.nix`, regenerate root `flake.nix`).
- Rewrite/retire `modules/den/aspects/core/nix/lix.nix`; pin
  `nix.package = pkgs.nixVersions.latest` in `core/nix/nix.nix`.
- Remove `lix-module.overlays.default` (`pkgs.nix:22-23`); fix `nix-eval-jobs` →
  `pkgs.nix-eval-jobs` (`colmena.nix:119`).
- `nix-flake-update`; confirm no `git.lix.systems` URLs remain in `flake.lock`.

**Gate (byte-identical):** the cortex toplevel `.drv` must be identical before/after:
```
nix eval --no-eval-cache --raw .#nixosConfigurations.cortex.config.system.build.toplevel.drvPath
```
(string-compare / nix-diff). Mismatch ⇒ investigate before apply.

**Baseline:** record CppNix wall/copies/heap (`NIX_SHOW_STATS`) next to the **Lix
baseline (~33.5s / 36.9s cpu / 5.9 GB / 235.77M copies)** — the reference Determinate
(Phase 2) will be compared against later.

**Apply (canary cortex, then fleet):** `nix-flake-build cortex && colmena apply-local
--sudo`. Confirm `nix --version` shows plain Nix and the daemon is standard. Roll out
host-by-host; k8s nodes (`axon-*`/`blade`/`uplink`/`bitstream`) last.

**Follow-through (the mission payoff):** point **hola's CI** (`~/Documents/repos/hola/ci`)
at CppNix too, so the parity harness proves byte-identical on the evaluator users run.

---

## A2 — Overlay C0 (`useGlobalPkgs=true`)

**The redundancy:** `home-manager.useGlobalPkgs = false`
(`modules/den/aspects/core/users/home-manager.nix`) makes each of the 3 users
(`shuo`/`sini`/`will`) `import nixpkgs` afresh + re-apply per-user overlays
(`nix-vscode-extensions` → `pkgs.vscode-marketplace.*`; `fenix` in dev aspects).
Measured: HM ≈ 46% of eval / 108M copies / 2.7 GB / 15s; `useGlobalPkgs=false` is the
3×-pkgs amplifier. (The deeper per-user *module-eval* redundancy is Phase 4.5 L2 — needs
the engine, **out of scope here**.)

**Steps:**
1. Hoist the per-user overlays (`nix-vscode-extensions`, `fenix`, any others) into the
   **system** overlay chain (`modules/flake-parts/pkgs.nix` /
   `core/nix/nixpkgs.nix`'s `sharedOverlays`). They're additive (`vscode-marketplace`,
   `fenix` add attrs; don't override core pkgs).
2. Set `home-manager.useGlobalPkgs = true` (`core/users/home-manager.nix`).
3. Reconcile any per-user `nixpkgs.config`/overlay that differs from the system.

**Gate (may legitimately shift):** re-eval the **4 drvPaths** — system toplevel
(master) + per-user `home.activationPackage.drvPath` (sini/shuo/will). *Ideally
byte-identical* (additive overlays → same derivations). If they shift, **`nix-diff`
the toplevel** old-vs-new to confirm the change is *only* the expected pkgs-sharing
artifact — **no user loses a package, no version regression**. Record the new baseline.

**Measure the win:** `NIX_SHOW_STATS` copies/heap/wall vs the A1 CppNix baseline —
quantify the pkgs-collapse (expect a meaningful slice of the 108M).

**Decision point (don't force it):** if a user's per-user `nixpkgs.config`/overlay
genuinely can't move to system (a real per-user divergence), `useGlobalPkgs=true` isn't
viable as-is — **stop and report**. That case *is* the cross-scope module-eval problem
(Phase 4.5 L2) which needs the engine, not config.

---

## Conventions (both)

- **Generated flake:** edit `modules/flake-parts/flake-file.nix`, regenerate
  (`nix run .#write-flake`); never hand-edit root `flake.nix`.
- **Format:** `nix fmt` (NOT bare `treefmt`).
- **Linear history:** rebase/ff-only; **auto-merge** (`gh pr merge --rebase --auto`)
  without asking.
- **Public repo:** no IPs/domains/ports/host-counts in commits or PR bodies.
- **Commits:** no `Co-Authored-By`, no bylines; stage files by name (never `git add -A`).
- **`nixidy-sync` hook** fires on `flake.lock` bumps → refresh the devshell
  (`nix develop -c true` / `direnv reload`) before committing, else the commit fails.
- **One agent per repo** (this is nix-config; the v3 agent is in gen-rebuild — no clash).
- **CI green before merge** (`fmt.yml`, `update-flakes.yml`).

## Success criteria

- **A1:** Lix gone, CppNix live on the fleet, cortex toplevel **byte-identical**,
  CppNix baseline recorded, hola CI on CppNix.
- **A2:** `useGlobalPkgs=true` (or a reported blocker), 4-drvPath gate satisfied
  (identical or `nix-diff`-explained), eval win measured, no environment regression.

---

*This is Wave A of the agreed dispatch order (see `project_hola`): runs now, parallel
to gen-rebuild v3; the hola engine (Phase 4.2, critical path) follows on gen-rebuild
v2; Den integration + cross-scope sharing + the zen comparison gate on the
byte-identical engine; Determinate (Phase 2) is the opportunistic velocity track.*
