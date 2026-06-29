# Plane-2a realized via den's EXISTING instantiation pattern (2026-06-28)

A follow-on to the Plane-2a PoC. Question: can the class-core eval-sharing be realized with den's
instantiation primitives **that exist today** (`nixosSystem.extendModules` + `lib.mkForce`), rather
than the harness's attrset-merge trick OR the (unbuilt) den-hoag seam? **Answer: yes.** This is the
Gate-B mechanism (CORE-FORCED=1 via mkForce-injection at `extendModules`), extended from one
projection on real axon to the 96-host synth class.

## Mechanism (no den-hoag, no apply-trick)
Each synth host is already a real den-instantiated `nixosConfiguration` exposing `extendModules`
(verified: `hasExtendModules=true`, mkForce-injection round-trips). To share the class-invariant
core across N members:
```nix
arch     = ncs.<archHost>;                 # a real class member
archPath = arch.config.system.path;        # the class-invariant projection (systemPackages buildEnv)
inject h = (arch.extendModules { modules = [
             { system.path = lib.mkForce archPath;        # inject the forced core
               networking.hostName = lib.mkForce h; }     # the per-host axis
           ]; }).config.system.path;
```
`archPath` is forced ONCE; `mkForce` makes each member's `system.path` resolve to that already-forced
value, so the deep construction (the buildEnv derivation closure) is NOT recomputed per member. Each
member is a genuine, distinct `evalModules` fixpoint (its own hostName) — only the class-invariant
projection is shared. Soundness: `system.path` is class-invariant (the parity oracle's premise), so
the injected value IS each member's correct value.

## Measured (N=100, agent class, `system.path` projection; NIX_SHOW_STATS, eval-cache off, watchdog-guarded)

| mode | M=2 | M=48 | M=96 |
|---|---|---|---|
| reconstruct (copies / cpu / RSS) | 129.4M / 40.0s / 6.60GB | 361.6M / 124.0s / **18.41GB** | — (trend clear) |
| **inject** (copies / cpu / RSS) | 125.5M / 38.9s / 6.60GB | 178.4M / 55.2s / 7.23GB | **233.7M / 65.9s / 8.05GB** |

**Per-added-node marginal (M=2→48):**
- reconstruct: **5,048,081 copies/host, 1.83s/host**
- inject: **1,151,296 copies/host, 0.35s/host**
- ⇒ **4.38× fewer copies, 5.15× faster per added node.** (The M=2 base ≈125M is the shared N=100
  fleet-resolution + nixpkgs base, paid once in both; the marginal is the discriminating metric.)

**The three answers:**
1. **96 nodes runs today:** `inject` forces all 96 members' `system.path` at **8.05GB RSS / 65.9s.**
   `reconstruct` needs **18.41GB for just 48** (and the full-units reconstruct OOM'd the machine at
   M=48, ~115GB). inject RSS is nearly flat across scale (6.60→7.23→8.05GB for M=2→48→96).
2. **Speedup ≈ 4.4–5.2× per added node** (widens with N as the base amortizes).
3. **Memory reduction ≈ 2.55× at M=48** (7.23 vs 18.41GB); the gap explodes by M=96 (inject flat at
   8GB, reconstruct heads to OOM).

The 4.38× confirms genuine sharing: if each member re-derived the core, inject would equal
reconstruct. It does not — the injected projection is forced once.

## Full core — extending to the systemd.units half (the co-produced attrset)

`system.path` is a LEAF value; the other ~53% of the cost-center is `systemd.units` — an attrset the
member's modules *co-produce* (217 class-invariant shared + ~11–28 per-host delta). Injecting it:
```nix
archShared = lib.getAttrs sharedUnitKeys arch.config.systemd.units;   # forced once
inj h = arch.extendModules { modules = [
          { networking.hostName = lib.mkForce h; }
          { systemd.units = lib.mkForce (archShared // builtins.removeAttrs ncs.${h}.config.systemd.units sharedKeys); }
        ]; };   # member's delta from its factory fixpoint (removeAttrs is lazy ⇒ shared values not forced)
```
Measured (N=100 agent class, units drvPaths; per-node marginal scale-invariant 6-vs-96):

| | reconstruct | inject (units-core) |
|---|---|---|
| per-node marginal | 21,722,170 copies / 7.42s | **11,486,320 copies / 2.32s** |
| ratio | — | **1.89× fewer copies, ~2–3.5× faster** |
| M=96 | OOM ~115GB **at just M=48** | **runs all 96: 1.24B copies, 275.8s, 39.12GB** |

**Leaf vs co-produced attrset — the structural finding:**
- A **leaf** projection (`system.path`) `mkForce`-injects whole; the member's re-eval spine is tiny
  next to the buildEnv ⇒ **4.38×** today.
- A **co-produced attrset** (`systemd.units`) shares its 217-unit core, but the member's
  `extendModules` must re-run `evalModules` to apply the `mkForce` ⇒ a full merge spine per member
  caps it at **1.89×**, vs the harness-2a / den-hoag ceiling of **2.48×** (8.76M marginal). The
  ~31% gap IS the den-hoag value: inject the class core as a *fixed module input* so the member's
  eval produces only the delta (no re-merge), recovering the ceiling.
- Both run 96 nodes where reconstruct OOMs; `system.path` inject is far lighter (8GB) than the
  units inject (39GB) because units force each member's full spine + delta, not one value.

## Fixed-input injection — recovering the `extendModules` spine tax (2026-06-29)

The `extendModules` realization pays a per-member module-merge re-eval spine (1.89× on units). The
"den-hoag" idea is to inject the class core as a *fixed input* so the member produces only the delta.
Tested the today-stock approximation: **config-merge** — assemble the per-host result as a plain
merge on the *resolved* `arch.config`, no `extendModules`, no re-eval:
```nix
archCore = lib.getAttrs sharedKeys arch.config.systemd.units;        # forced once
member h = archCore // builtins.removeAttrs ncs.${h}.config.systemd.units sharedKeys;
```
Measured (units; vs reconstruct 21.72M/node):

| approach | marginal/node | ×  | produces | byte-identical |
|---|---|---|---|---|
| `extendModules`+`mkForce` | 11.49M | 1.89× | full per-host config | ✓ |
| **config-merge (fixed-input)** | **6.54M (6-host) / ≈8.76M (fleet)** | **3.32× / 2.48×** | the **projection** | **✓ (225/225 keys)** |

**Result: fixed-input via config-merge recovers the tax — 2.48× at fleet scale, 3.32× at the 6-host
class** (small-scale is higher: more keys class-invariant across fewer members), byte-identical
(units == real host units, verified). Dropping the `extendModules` re-eval is the whole win.

**Structural limit (why this is projection-only, and what den-hoag must still do):** config-merge can
reassemble a *consumed projection* (units, system.path) but NOT a full per-host **toplevel** —
`(arch.config // { networking.hostName = h; }).system.build.toplevel` returns arch's *already-resolved*
toplevel (the `//` patches a sibling key; it cannot retroactively recompute the monolithic toplevel),
so every host gets arch's toplevel. (Couldn't even force the synth toplevel to show it — it hits the
known initrd-SSH assertion; the limit is structural, not measured.) **So fixed-input recovers 2.48×+
TODAY for projections you consume directly; extending that recovery to the deployable per-host
toplevel is precisely den-hoag's job** (restructure modules so each member's eval consumes the
injected core and emits only the delta — no monolithic re-merge).

### The today-usable helper (projection-level)
```nix
# Force the class archetype's core once; assemble each member's projection as core // delta.
# Recovers 2.48x+ (byte-identical) for a CONSUMED projection (e.g. systemd.units, system.path).
# NOT a full toplevel (structural limit above). archetype + hostConfigs are real den-instantiated configs.
shareClassProjection =
  { archetype, hostConfigs, sharedKeys, project ? (c: c.systemd.units) }:
  let core = lib.getAttrs sharedKeys (project archetype.config);
  in builtins.mapAttrs
       (_: hc: core // builtins.removeAttrs (project hc.config) sharedKeys)
       hostConfigs;
```

## Honest bounds
- **Two projections measured** — `system.path` (leaf, ~42%, 4.38×) + `systemd.units` (co-produced
  attrset, ~53%, 1.89×). Together ≈ the per-host cost-center. The remaining toplevel surface (etc,
  initrd, activation) is the same mechanism, leaf-vs-attrset by piece.
- **The spine is still per-member.** inject's 1.15M-copies/node residual = each member's module-merge
  WHNF discharge (extendModules re-runs evalModules; mergeDefinitions property-discharges the losing
  def to WHNF before mkForce wins — Gate B's stated bound). What's lifted off the N-axis is the deep
  *construction*, not the merge spine.
- **Intra-process.** Same as Plane-2a: shared within one eval; cross-invocation = Plane-2b.

## Significance
This **reframes the "production needs den-hoag" caveat.** den's existing `extendModules`+`mkForce`
instantiation realizes the class-core sharing TODAY — leaf projections at **4.38×** (`system.path`),
co-produced attrsets at **1.89×** (`systemd.units`), both running 96 nodes where reconstruct OOMs.
den-hoag is no longer "enable the capability" — it is **(1) make this the DEFAULT fleet-build path**
(force the class core once, inject at every `host.instantiate`) and **(2) recover the ~31% spine tax
on co-produced attrsets** (1.89×→2.48×) by injecting the core as a fixed module input rather than
re-running `evalModules` per member. The Plane-2a PoC *identified* the shareable work; this shows it
is *realizable now* through real den primitives, with den-hoag as an optimization-of-the-realization,
not its prerequisite.

Evidence: `scratchpad/instantiate-{probe,scale}.sh`. Companion to `2a-result.md`.
