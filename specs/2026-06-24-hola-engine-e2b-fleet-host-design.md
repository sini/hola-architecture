# hola Engine — E2b: nix-config Fleet Host Parity (full-surface, pure) — Design Spec

> **Status:** approved design (brainstorm + empirical recon), pre-implementation (pending spec-review + user review).
> **Date:** 2026-06-24.
> **Increment:** hola Phase 4.2, Wave C, sub-increment **E2b** (production-scale, the Wave-D-target proof; follows E2a @ `github:sini/hola` 1829fae).
> **Repo:** `~/Documents/repos/hola` (`github:sini/hola`).
> **Reuses:** the E1 engine (`adapter.engines.engine`) UNCHANGED — verified usable for ALL three target hosts. Mirrors E2a's full-surface lib-doctoring, adapted to nix-config's flake-parts/dendritic + multi-channel shape.

## 1. Context & motivation

E2a proved the engine byte-identical on a Den *template*. **E2b proves it on real nix-config *fleet
hosts*** — the production-scale, Wave-D-target proof ("Den's swap is just pointing outputs.nix at the
engine"). Decided with the user: host progression **bitstream → blade → cortex**, a **pure**
`nix flake check` gate (not impure), nix-config wired as a committed `github:sini/nix-config` ci input
(validation-only — explicitly NOT a long-term coupling).

**Empirical recon (nix-config @ `8f84aa62`, all pure eval):**
- `flake.nix:6` `outputs = inputs: flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./modules)` — plain `inputs`, **re-invokable**.
- Host toplevel built by **den** via the per-channel seam `modules/den/schema/host.nix:116-141`: `nixos-unstable → inputs.nixpkgs-unstable.lib.nixosSystem`, `nixpkgs-master → inputs.nixpkgs-master.lib.nixosSystem`. So lib enters via **`inputs.<channel>.lib`**, NOT `inputs.nixpkgs.lib` (26.05 stable) and NOT flake-parts `nixpkgs-lib`.
- `inputs.self` is the **one input `getFlake` does NOT supply** (`nc.inputs ? self == false`) and `mkFlake` requires it. On the toplevel path it is BOTH string-coerced (`self + "/.secrets/…"`, `host.nix:391`) AND forced as `self.overlays.default` (`nixpkgs.nix:16`). ⇒ the knot must be the **lazy `out` fixpoint carrying `outPath`/`sourceInfo`**: `self = out // { outPath = nc.outPath; inherit (nc) sourceInfo; }`. (A bare `self = out` throws on string-coercion; a static `{ outPath = …; }` carrier throws `overlays missing`. The lazy carrier supplies both — verified.) No `self.nixosConfigurations.<other>` cross-host force was found on the toplevel path, so the lazy knot suffices (no full fixed-point needed).
- Hosts + channels (drv-name-confirmed): **bitstream**=`nixos-unstable`=`567a49d`; **blade**,**cortex**=`nixpkgs-master`=`5e8ca42`. Pure eval, no IFD (facter via `reportPath`), secrets are store-path refs not forced by the toplevel.

**Two facts that make this pure + single-engine:**
- **`getFlake` exposes resolved `.inputs`, and a rev-locked `getFlake` is pure** (verified: `nc.inputs.nixpkgs-unstable.rev == 567a49d` evaluated with NO `--impure`). So the runner gets nix-config's ~30 resolved inputs for free, purely — no input mirroring, no impurity.
- **`lib/modules.nix` (and `lib/types.nix`) are byte-identical between `567a49d` and `5e8ca42`** (verified `diff -q`). So the existing 567a49d-vendored engine is the *correct* engine for the master-channel hosts too (vendored body ≡ each host's channel `modules.nix`), keeping byte-identity meaningful per E2a-D5. **No master re-vendor; one engine for all three hosts.**

## 2. Decisions (locked)

| # | Decision | Rationale |
|---|---|---|
| E2b-D1 | **Full-surface, pure, gating** — re-invoke nix-config's raw `outputs` with the host's channel input's `.lib` doctored to `engine.lib` + a lazy self-knot | Routes the host's WHOLE eval (den aspect resolution, `den.hosts`, host re-instantiation, the toplevel) through the engine. Pure (rev-locked `getFlake`), so it's a `nix flake check` gate, same tier as `den-parity`/`realHost`. |
| E2b-D2 | **nix-config = committed `github:sini/nix-config` ci input** (rev-locked); validation-only | User: "github ref works — just for validation, not a long-term path." A rev-locked input makes `getFlake`/`.inputs` pure; the github ref lets the remote GitHub-Actions gate fetch it. Removable later. |
| E2b-D3 | **One vendored body, re-seeded per channel** (`fleetEngineLib`); doctor the host's nixpkgs INPUT (`nixpkgs-unstable` for bitstream, `nixpkgs-master` for blade/cortex) | The engine is **re-instantiated on the host's channel lib** (`import ./engine { lib = channelLib; }`), so vanilla=identity reproduces the host's REAL build and the engine substitutes ONLY `modules.nix` on that same channel lib. `modules.nix`+`types.nix` are byte-identical across the revs (verified, E2b-D5), so the single vendored body is correct for both channels. **The fixture carries `channelInput` (the nixpkgs INPUT name), NOT the den `channel` name** — bitstream's den channel is `"nixos-unstable"` but its input is `"nixpkgs-unstable"`; conflating them indexes a missing attr (blade/cortex's `"nixpkgs-master"` matches both, masking it). |
| E2b-D4 | **Host progression bitstream → blade → cortex, each a separate gate** | bitstream = smallest, zero pin distance (de-risk). blade = complex hardware (intel+nvidia-prime), NO microvm. cortex = + microvm guest (cortex-cuda). Increasing surface; isolate failures. |
| E2b-D5 | **Engine UNCHANGED; channel-`modules.nix`-identity asserted** | E2b is corpus + adapter wiring only. Add a check that the vendored `modules.nix` ≡ BOTH `nixpkgs-unstable` and `nixpkgs-master` `lib/modules.nix` (currently identical) — so a future master/unstable `modules.nix` drift is caught (it would re-open the E2a-D5 pin ambiguity for master hosts). |

## 3. Mechanism (the spine — empirically verified for bitstream)

```nix
# lib/corpus/den-fleet.nix  (sketch)
{ lib }:
{
  # channelInput = the nixpkgs INPUT NAME to doctor (e.g. "nixpkgs-unstable"), which is DISTINCT
  # from the den `channel` name on the host (bitstream's den channel is "nixos-unstable" but the
  # input is "nixpkgs-unstable"; blade/cortex use "nixpkgs-master" for both, which masked this).
  mk = { nixConfig, host, channelInput }:   # nixConfig = the committed nix-config flake input
    {
      gate = "drvPath";
      denFleet = { inherit nixConfig host channelInput; };
    };
}

# lib/adapter.nix — runDenFleet is CHANNEL-SEEDED: the doctored lib is built from the HOST'S OWN
# channel lib (NOT a global engine, which carries hola's root-nixpkgs 567a49d → a foreign-lib
# build that is internally vanilla≡engine but is NOT the host's real build). `doctor : channelLib ->
# lib`; vanilla = identity (the host's REAL build), engine = vendored-modules-on-the-channel-lib.
fleetEngineLib = baseLib: (import ./engine { lib = baseLib; }).engine.lib;   # re-instantiate engine on baseLib
runDenFleet = doctor: fx:
  let
    f   = fx.denFleet;
    nc  = f.nixConfig;                                  # rev-locked flake input → nc.inputs is pure
    chan = nc.inputs.${f.channelInput};
    raw = import (nc.outPath + "/flake.nix");
    out = raw.outputs (nc.inputs // {
            # lazy self-knot: `self` is the ONE input getFlake does NOT supply (nc.inputs ? self == false),
            # and the toplevel both string-coerces it (host.nix:391 `self + "/.secrets/…"`) AND forces
            # `self.overlays.default` (nixpkgs.nix:16). So the knot must carry outPath/sourceInfo AND be
            # the lazy `out` fixpoint (to supply the `overlays` flake output). A bare `self = out` THROWS.
            self = out // { outPath = nc.outPath; inherit (nc) sourceInfo; };
            ${f.channelInput} = chan // { lib = doctor chan.lib; };  # id ⇒ real build; fleetEngineLib ⇒ engine
          });
  in
    out.nixosConfigurations.${f.host};                  # carries .config.system.build.toplevel.drvPath
```

**Empirically verified (pure, channel-seeded):** the **vanilla (identity) arm reproduces each host's
REAL build** — bitstream `70xb6lxav…-bitstream-…567a49d.drv` (= `nc.nixosConfigurations.bitstream`),
blade `z1j54phn…-blade-…5e8ca42.drv` (= the real master-channel build) — and the **engine arm is
byte-identical to it** on bitstream + blade. (The earlier global-`engines.engine` form produced an
artificial `10vgh8b8…` build, not the real one — that's why channel-seeding is required.) The lazy
`outPath`-carrying self-knot is load-bearing (a static carrier throws `overlays missing`).

The gate (`ci/tests/den-fleet-parity.nix`) asserts, per host,
`(parity.drvPathGate { a = runDenFleet (l: l) fx; b = runDenFleet fleetEngineLib fx; }).identical == true`
— direct `drvPathGate` (NOT `compose.engineParity`, which hardwires `runHost`), exactly as E2a's
`den-parity` does.

## 4. What it proves / honest unknowns

E2b proves the engine byte-identical on **real production fleet configs** at increasing scale, through
nix-config's full flake-parts/dendritic + den machinery — the strongest pre-Wave-D evidence. Honest
unknowns (the harness is the backstop; a divergent `toplevel.drvPath` localizes via `parity.locate`,
and is interpreted under E2b-D5's vendored≡channel-`modules.nix` identity, so a divergence is an
unambiguous engine-or-Den-lib-escape, not rev drift):
- **Self-knot sufficiency:** the lazy `outPath`-carrying knot (§3) is **verified byte-identical on bitstream AND blade**; no `self.nixosConfigurations.<other>` cross-host force was found on the toplevel path. If some host forces a cross-host self ref, the knot must be made lazier or that host deferred.
- **cortex microvm guest:** the cortex-cuda microvm sub-eval is a fresh evalModules — it runs on the doctored channel lib too (module-arg `lib`), so it *should* be owned, but cortex is the last gate precisely to surface this.

## 5. Components / files

| File | Status | Role |
|---|---|---|
| `ci/flake.nix` | edit | Add `nix-config.url = "github:sini/nix-config"` (committed/locked); thread it to the corpus via specialArgs (`denFleet = { nixConfig = inputs.nix-config; }`). |
| `lib/corpus/den-fleet.nix` | new | `mk { nixConfig, host, channel }` → fx carrying the fleet-run data. |
| `lib/adapter.nix` | edit | `runDenFleet engine fx` (§3) — channel-aware full-surface doctor + lazy self-knot; export it. |
| `lib/corpus/default.nix` | edit | Register `denFleet` (gate `drvPath`). |
| `ci/tests/den-fleet-parity.nix` | new | Gating: `den-fleet-parity.<host>` for bitstream (incr 1), then blade, cortex (incrs 2-3). |

Engine (`lib/engine/**`) unchanged. Optionally extend `vendor-integrity` (or a new `channel-modules-identity` test) to assert vendored `modules.nix` ≡ both channels' (E2b-D5).

## 6. Increments (each parity-gated)

- **E2b-1 — bitstream** (`channel = "nixpkgs-unstable"`, zero pin distance, existing engine). The load-bearing first proof: the fleet seam (re-invoke `outputs` + doctor channel lib + self-knot) is byte-identical on a real host. **Empirically pre-verified** in recon (bitstream evals pure to `…-nixos-system-bitstream-…567a49d.drv`).
- **E2b-2 — blade** (`channel = "nixpkgs-master"`, complex hardware, no microvm). Same machinery, master channel; proves the cross-channel single-engine soundness in practice.
- **E2b-3 — cortex** (`channel = "nixpkgs-master"`, + microvm guest). The full monty; surfaces any microvm-sub-eval gap.

## 7. Out of scope

- No engine change (E1 body reused, proven sufficient for all channels). No selection (E3), no gen-rebuild.
- nix-config-as-input is **validation-only** (removable); E2b is not a permanent hola↔nix-config coupling.
- If a host diverges, the *fix* is a scoped engine follow-up (a real Den/engine gap), not folded into E2b's corpus wiring; a `self`-knot-forcing host may be deferred rather than block the increment.

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **Self-knot forces a cross-host ref** on some host's toplevel. | Recon found none on the toplevel path; lazy knot. If a host forces it, defer that host (the others still gate). |
| **Channel `modules.nix` drift** (master vs unstable diverge in future). | E2b-D5 asserts vendored ≡ both channels' `modules.nix`; a drift fails that check, flagging the need for a channel-rev engine before trusting master-host parity. |
| **nix-config not public / GitHub-Actions can't fetch.** | `github:sini/nix-config` must be pushed/public for the remote gate; local runs work against the committed lock regardless. Validation-only, so a local-only gate is acceptable if the repo stays private. |
| **Heavy eval (cortex) time/memory** in CI. | drvPath eval only (no build); cortex is the last increment and can be a `nix run` evidence variant if CI-time is a concern (but pure-gating is the default). |
| **`raw.outputs` needs an input the doctor omits.** | `nc.inputs` supplies the full resolved set EXCEPT `self` (the one input `getFlake` omits, `nc.inputs ? self == false`) — the lazy `outPath`-carrying knot provides it. The runner otherwise only *overrides* the one channel input. Verified: nothing else omitted (bitstream+blade eval clean). |

## 9. References

- E2a spec/impl (the pattern E2b mirrors): `specs/2026-06-24-hola-engine-e2a-den-template-design.md`; `lib/corpus/den-template.nix`, `adapter.runDenTemplate`, `ci/tests/den-parity.nix`.
- nix-config @ `8f84aa62` (branch `main`): `flake.nix:6` (outputs), `modules/den/schema/host.nix:116-141` (channel→nixosSystem seam), `:391-392` (self as path base). Hosts: bitstream/axon-0{1,2,3}/blade/cortex/uplink.
- Verified facts: `getFlake` exposes pure `.inputs` (rev-locked); `modules.nix`+`types.nix` byte-identical `567a49d`↔`5e8ca42`; bitstream pure toplevel `…567a49d.drv`.
- Memory: `project_hola` (Wave C / E2a + the E2b note), `project_nix_config_migration`, `project_den_architecture`.
