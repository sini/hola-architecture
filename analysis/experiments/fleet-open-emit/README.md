# Fleet open-emit demonstration — evidence (build-order step 1)

The first **end-to-end OPEN cross-host emit on the real axon fleet**: a host reads a
peer's *resolved* `config` across hosts. Implements step 1 of the fleet-eval-sharing
build order (`../../../specs/2026-06-25-fleet-eval-sharing-architecture.md` §10); design in
`../../../specs/2026-06-26-fleet-open-emit-demo-design.md`. **A measurement, not a feature.**

## What was wired (throwaway)

A `persist-claims` quirk whose emit is **open** — `{ host, config, ... }` — reading the
producing peer's `config.users.users.frr.uid` (`978`, fixed by the `deterministic-uids`
aspect, class-invariant across axon-02/03). A **scoped `pipe.collect`** aggregates the axon
siblings; a `nixos` consumer surfaces the collected claims to `environment.etc` so the
cross-host collect is demanded. Rides `services.bgp.spoke` (axon-only, where frr is
enabled) ⇒ zero host-file logic beyond a one-line `includes` entry per axon host.

- **Patch:** `persist-claims-demo.patch` (6 files, 68 insertions; nix-config branch
  `demo/persist-claims-open-emit` @ `bc6a0cb7`, off main `384297df`, **never merged**).
- frr is the read because it is the **only host-level declarative service uid on the whole
  axon class** — the stateful services (postgres/longhorn/prometheus) run as k3s pods, so
  their ownership is a pod `securityContext` uid, not `config.users.users.<svc>.uid`; media
  (1027) is axon-01-only.
- **It is the first open emit in nix-config.** Every existing emit (`k3s-nodes`,
  `bgp-peers`, `host-addrs`, `resolved-users`) reads only the *entity* record
  (`host.*`/`user.*`), never the resolved nixos `config`. The open emit was genuinely
  dormant; this exercises it.

## Reproduction

```
git -C nix-config worktree add .worktrees/x demo/persist-claims-open-emit   # or: git apply persist-claims-demo.patch
cd nix-config/.worktrees/x
FEAT='--extra-experimental-features "nix-command flakes pipe-operators" --accept-flake-config'

# M1 — capability (it resolves)
nix eval $FEAT '.#nixosConfigurations.axon-02.config.environment.etc."persist-claims-demo.json".text' --raw

# M2/M3 — sizing (NIX_SHOW_STATS)
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=B.json nix eval $FEAT '.#nixosConfigurations.axon-02.config.users.users.frr.uid'                                  # B
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=A.json nix eval $FEAT '.#nixosConfigurations.axon-02.config.environment.etc."persist-claims-demo.json".text' --raw  # A
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=T.json nix eval $FEAT '.#nixosConfigurations.axon-02.config.system.build.toplevel.drvPath' --raw                    # T
```

Host = `axon-02`, nixpkgs-unstable `567a49d`, Nix 2.34.7, 2026-06-26. Metric =
`nrThunks`/`nrFunctionCalls`/`nrOpUpdateValuesCopied`/`cpuTime`. Raw: `stats-{B,A,T}*.json`.

## M1 — capability: PASS

```json
[{"host":"axon-02","path":"/persist/axon-02/frr","uid":978},
 {"host":"axon-01","path":"/persist/axon-01/frr","uid":978},
 {"host":"axon-03","path":"/persist/axon-03/frr","uid":978}]
```

axon-02 reads axon-01's and axon-03's **resolved** `config.users.users.frr.uid`.
**Exactly 3 entries** — the axon class, not the 7-host fleet: the scoped `collect`
(sibling-environment) bound is structurally visible in the result.

## M2 / M3 — sizing

| eval | thunks | fn-calls | **copies** | cpu | maxRSS |
|---|---|---|---|---|---|
| **B** — 1-host `frr.uid` slice (module-merge, no drv) | 10.4M | 9.2M | **2.68M** | 2.56s | 715 MB |
| **A** — cross-host open collect (3 hosts) | 15.4M | 12.6M | **10.6M** | 4.81s | 1262 MB |
| **T** — full `toplevel.drvPath` (the 94% cost-center) | 36.9M | 25.8M | **32.3M** | 12.86s | 3116 MB |

### M3 — the open read is the module slice, NOT the derivation construction: PASS
The discriminating metric is **copies** (`nrOpUpdateValuesCopied`) — the cortex profile's
~94% wall cost-center. Resolving a config *value* costs **B = 2.68M copies = 8.3% of T's
copies**; the derivation construction (**T − B = 29.6M copies = 91.7%**) is what the open
read avoids (no drvPath forced — `frr.uid` is an `int`). This is the architecture spec
§4(a) claim, measured: a Tier-2 *value* read ≈ the module-merge slice per touched peer, not
a toplevel.

**Honest bound (Gate-B):** fn-calls are *not* discriminating — B's 9.2M fn ≈ the full host
module fixpoint (the cortex profile's ~9.0M for the `hostName` fixpoint). Reading *any*
single option forces ~the whole module-merge layer (cost-center A), because the module
system evaluates the option set. Only the **derivation-construction copies** are avoided.
So "cheap" means *cheap in the 94% cost-center*, not cheap in absolute eval — exactly the
Gate-B caveat (the real def is still WHNF-touched).

### M2 — scoped collect is bounded to matched peers, not the fleet: PASS
- **A = 3.97× B in copies** (≈ the 3 axon hosts + collect/consumer overhead), **not 7×**
  (the fleet). The collect forces the matched siblings only.
- **A forced zero peer toplevels** — a single forced peer toplevel would add ~30M copies
  (cf. T); A's 10.6M copies = three *module slices*, no derivation construction cross-host.
- **fn-calls only 1.37× B**, because the nixpkgs/module-system baseline is thunk-memoized
  across same-system hosts (the profile's "fleet ≈ 1.45× one host"). The *incremental* cost
  of each additional peer is the per-host module-merge copies, not a repeated baseline.

The binary "forces axon-02 alone" laziness was already proven (Gate A
`/tmp/d5_lazy_probe.nix`); this adds the **real-fleet magnitude**. The `collect` (scoped) vs
`collectAll` (global) *difference* is a fleet-scale (multi-environment) property and is **not
demonstrable on the single-environment axon fleet** (the emit is axon-only, so both would
gather the same 3 hosts); the structural 3-entry result + the bounded ~4× sizing stand in
for it here.

## Conclusion

All three claims hold on the real fleet: **the open cross-host config read works (M1), is
bounded to the scoped matched peers (M2), and avoids the 94% derivation-construction
cost-center (M3, in copies).** The capability nix-config keeps dormant is usable and
affordable today — sizing what the §8a-S2 cone-expander and Plane-2a class-sharing then
buy at 100s of hosts. The branch is discarded; this writeup + patch + stats are the record.
