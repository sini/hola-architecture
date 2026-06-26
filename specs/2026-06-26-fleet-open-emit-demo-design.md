# Real-axon open-emit demonstration — design (fleet build-order step 1)

> **Status:** design, approved in brainstorming 2026-06-26. Implements **step 1** of the
> fleet-eval-sharing build order (`specs/2026-06-25-fleet-eval-sharing-architecture.md` §10):
> *"Unlock the open emit on real axon."* A **measurement**, not a shipped feature.
> **Date:** 2026-06-26.

## 1. Goal

Prove on the **real axon fleet** that an **OPEN cross-host quirk** (a host's relation
reads a peer's *resolved* `config`) is affordable **today** — the capability den ships
but nix-config keeps **dormant** (§0 of the architecture spec). Concretely, demonstrate
end-to-end that a central collector reading `config.users.users.frr.uid` across
axon-01/02/03 via a **scoped `pipe.collect`**:

1. **resolves** (real peer config crosses hosts), and
2. is **cheap** — it forces the per-host **module-merge slice** (a uid is an `int`), **not**
   the ~94% derivation-construction cost-center (no host `toplevel.drvPath`), and
3. forces **only matched peers** (scoped `collect`), the real-fleet size of the Gate-A
   laziness already proven binary in `/tmp/d5_lazy_probe.nix`.

This is the **first end-to-end artifact** exercising the open emit on the real fleet —
the thing that has value den/nix-config lack today. It is *not* a backup feature and *not*
the `pipe.reads` cone-expander (that is step 2, in den).

## 2. Why frr, why this read

The only **host-level declarative service uids** on the axon class are **frr (978, all
three hosts, via `services.bgp.spoke`)** and **media (1027, axon-01 only)**. The
"interesting" stateful services (postgres/longhorn/prometheus) run **inside k3s as pods**,
so their ownership is a pod `securityContext` uid, **not** `config.users.users.<svc>.uid`
on the NixOS host. `frr.uid` is the one resolved-ownership read that exists across the
whole class — and it is **class-invariant** (`978` byte-identical across axon-02/03, the
`deterministic-uids` aspect), so under Plane 2 it would resolve once per class.

The canonical Tier-2 framing is the architecture spec §8b (a persist-claim for external
backup that needs `uid`/`gid` for ownership). frr is the concrete instance of that pattern
that the real axon fleet can actually exercise.

## 3. The wiring (throwaway nix-config branch)

Branch `demo/persist-claims-open-emit` in a **worktree** at
`nix-config/.worktrees/persist-claims-open-emit`, branched from committed **main**
(isolated from any in-progress edits in the main checkout). **Never merged** — captured as
a `.patch` for reproducibility, then discarded.

- `modules/den/quirks/persist-claims.nix`
  ```nix
  { den.quirks.persist-claims.description =
      "Per-service persist dir + resolved owner uid for external backup"; }
  ```
- The **OPEN emit**, attached to the axon-shared aspect that carries the frr user
  (`services/bgp`, reached by all axon via `services.bgp.spoke`):
  ```nix
  persist-claims = { host, config, ... }: {
    host = host.name;
    path = "/persist/${host.name}/frr";
    uid  = config.users.users.frr.uid;   # OPEN ⇒ hasAnyConfigThunk=true ⇒ B′ peer resolve
  };
  ```
- **Two** collect policies in `modules/den/policies/pipes.nix`, so the contrast is
  measurable in the same eval:
  - `collect-persist-claims` — **scoped** `pipe.collect (<axon-class predicate>)` — the
    demo (architecture spec §8b Form C, minus the not-yet-built `pipe.reads`).
  - `collect-persist-claims-naive` — **`collectAll ({ host, ... }: true)`** — the Form-B
    anti-pattern baseline (the unscoped shape the future S2 lint rejects). Wired only as the
    measurement contrast.

**Open implementation detail (resolve against the real scope tree during the plan):** the
**locus** of the scoped collector — cluster scope (à la
`cluster-collect-media-scratch-exports`) vs a designated axon host collecting fleet
siblings. Constraint: the predicate must be **scoped** (not `collectAll (_: true)`) **and**
must actually force peers, or M2/M3 are vacuous. Match `policies/fleet.nix`'s real tree.

## 4. Dev loop

`--override-input den` is the den dev loop (and the mechanism that carries into step 2,
where `pipe.reads` *is* a den-framework change). For **step 1 nothing is built into den** —
the demo uses only shipped den surface (`pipe.collect`), so the override just pins the
fleet's existing den. The new code lives entirely in the nix-config branch.

Eval entry (real fleet): `nix eval` the collector attribute on the axon hosts'
`nixosConfigurations`; metric via `NIX_SHOW_STATS`.

## 5. The measurement (durable record)

Three measured claims, each with a concrete probe on the real branch eval:

- **M1 — capability (it resolves).** The scoped collector value =
  `[{ host="axon-01"; uid=978; … }, { "axon-02"; 978; … }, { "axon-03"; 978; … }]` — real
  resolved peer config crossing hosts. Pass = the list is produced and uids are the real
  `978`.
- **M2 — scoped forces only matched peers (real-fleet sizing of Gate A).** `NIX_SHOW_STATS`
  A/B: eval `collect`-scoped-to-one-host vs `collectAll`-of-all; the thunk/copy/fn-call
  delta shows scoped ≈ matched-peers-only while `collectAll` ≈ N×. The *binary* "forces
  axon-02 alone" mechanism is already proven (Gate A `/tmp/d5_lazy_probe.nix`); M2 adds the
  **real-fleet** magnitude, it does not re-derive the mechanism. Pass = `collectAll`
  thunk-count materially exceeds scoped (≈ proportional to host count).
- **M3 — cheap (module slice, not derivation construction).** `NIX_SHOW_STATS` A/B/C with
  C = a host's full `system.build.toplevel.drvPath`: scoped-uid eval ≪ toplevel, and no
  host toplevel is forced by reading the uid. Pass = the open read's cost is the module
  slice, orders of magnitude below the toplevel (which is the 94% cost-center).
- **Class-invariance (restate, not re-measure).** `978` byte-identical across axon-02/03
  (deterministic-uids) ⇒ under Plane 2a it resolves once per class.

### Durable vs throwaway
- **Durable** (papers `analysis/experiments/fleet-open-emit/`): an evidence writeup +
  the branch `.patch` + the exact `nix eval` / `NIX_SHOW_STATS` commands + the M1/M2/M3
  numbers + conclusion. The measurement of record.
- **Throwaway**: the nix-config worktree/branch (deleted after capture).

## 6. Success criteria

The demonstration **succeeds** iff:
1. M1 produces the cross-host resolved-uid list on the real axon fleet (capability proven), and
2. M2 shows the scoped `collect` cost scales with *matched* peers while `collectAll` scales
   with the *fleet* (the affordability lever is real), and
3. M3 shows the open read costs the module slice, not the derivation-construction
   cost-center (Tier-2 is cheap, per architecture spec §4(a)).

A result where M2 shows scoped == collectAll (no scoping benefit) or M3 shows the read
forces toplevels would be an **honest negative** worth recording — but Gate A/B predict
success.

## 7. Boundaries

- No reusable den aspect (the scope-up to a shippable `backup-claims` feature was
  **declined** — step 1 is a measurement).
- No `pipe.reads` / S2 cone-expander (step 2, den-framework).
- No nix-config merge; no den change.
- Soundness/parity-gate work (per-class byte-identical validation) is Plane 2a (step 3),
  not here — this step only exercises and sizes the open emit.

## 8. References

- Architecture: `specs/2026-06-25-fleet-eval-sharing-architecture.md` (§0 value test, §4
  Tier-2, §8b worked persist-claims example, §10 build order step 1).
- Gate A laziness: `/tmp/d5_lazy_probe.nix` (binary "matched-peers-only", workflow
  `wh0ygg53t`).
- den surface: `policy-effects.nix:296-346` (pipe API), `resolve.nix:392` (config-dep
  boundary), `:393-408` (`hasAnyConfigThunk`), `:468` (`hostConfigs` B′). Open-emit
  precedent: den `templates/fleet-demo/modules/aspects/features/hostfile.nix:15-20`
  (`host-addrs` reads `config.networking.hostName`) + `policies/pipes.nix:30-36`
  (`collect-host-addrs` scoped collect).
- nix-config anchors: `axon-0N.nix:48-63` (aspect class), `deterministic-uids.nix:136`
  (frr 978), `services/bgp/bgp.nix:342` (frr user), `policies/pipes.nix` (real collect
  policies, e.g. `cluster-collect-media-scratch-exports`), `policies/fleet.nix` (scope
  tree).
- Memory: `project_hola`, `RESUME-fleet-architecture.md`.
