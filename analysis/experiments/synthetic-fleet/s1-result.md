# Fleet seam S1 — result (2026-06-28)

`plans/2026-06-28-fleet-seam-s1-per-sid-hostconfig.md`. Kill den's global all-or-nothing
`hasAnyConfigThunk`-gated `hostConfigs` map → structural host-scope attrset (`hostConfigScopeIds`,
O(1) `?`-membership) + lazy memoized per-sid builder (`hostConfigFor`), threaded through
`assemble-pipes.nix`. den commit `b3449c8b` on `feat/s1-per-sid-hostconfig` (off
`fix/broadcast-home-pool-to-host` @4911b7f2; den worktree, NOT pushed).

## The change (4 files, +303/−105)
- `nix/lib/aspects/fx/resolve.nix` — `anyConfigDepThunk` = the old `hasAnyConfigThunk` scan body
  verbatim, now consumed ONLY by the `bprimeEdges` guard (no longer gates `hostConfigs` building);
  `hostConfigScopeIds = lib.genAttrs (attrNames specsByHost) (_: true)` (ATTRSET, not list);
  `builtConfigs = lib.mapAttrs … specsByHost` (lazy per-sid); `hostConfigFor = sid: builtConfigs.${sid}`.
- `nix/lib/aspects/fx/assemble-pipes.nix` — `(hostConfigScopeIds, hostConfigFor)` pair threaded
  through `producerConfigs` (`? sid` membership, `hostConfigFor` value reads), `resolveEntry`/
  `resolveThunks` (defer on `== {}`, signal-only), every stage interpreter, the `:442`/`:833` value
  call sites. `grep hostConfigs` → only comments.
- `nix/lib/aspects/fx/spawn-node.nix` — `hostConfigs = null` → empty-attrset signal.
- `templates/.../deadbugs/s1-per-sid-hostconfig-laziness.nix` — NEW fixture: a local-only config-dep
  emit + a config-dep scoped collect; asserts a peer whose `.instantiate` throws is NOT built unless
  a config-dependent collected edge actually matches it (the footgun-killed invariant).

## The 5 reviewer landmines — all handled
1. `hostConfigScopeIds` is an **attrset** (`?`-membership O(1)) — NOT a list + `elem` (the O(N²·D)
   open-emit-hot-path regression the plan reviewer caught).
2. `bprimeEdges` gated on `anyConfigDepThunk` (config-dep PRESENT, ⟺ old `hostConfigs != null`), NOT
   host-presence — closed fleets stay zero-cost (no inert `specsByHost`/B′ construction).
3. `null ≡ {}` collapse documented (sound given ≥1 host produces output; the zero-output degenerate
   now defers = more correct).
4. `resolveEntry`/`resolveThunks` thread only `hostConfigScopeIds`; `hostConfigFor` lives solely in
   `producerConfigs` (the sole value consumer).
5. `markConfigThunks` / `#623 markedExposed` untouched.

## Validation — byte-identical, zero regression
- **den CI:** clean fix-branch `🎉 1052/1052` → post-S1 `🎉 1054/1054` (all 1052 originals green +
  the 2 new fixture tests). Targeted: `bprime-basedrain-crosshost 2/2`, `pipe-broadcast 11/11`,
  `pipe-config-scope 3/3`, `pipe-scope 18/18`.
- **Synth fleet:** `den-debug.classKey` N=10 byte-identical, github-pin (pre-S1) vs
  `--override-input den path:<s1-worktree>` (post-S1).
- **Real axon (the load-bearing gate):** `nixosConfigurations.{axon-02,axon-03}.…toplevel.drvPath`
  **byte-identical** pre-S1 vs post-S1 (`m88glzsg…`, `9y1dmyp4…`). axon-02/03 carry the two *local*
  age-secret config-dep emits that flip the old global flag — so byte-identity here proves S1's split
  changes nothing observable on the exact production case it targets.
- **B′ cycle preserved:** `builtConfigs` depends only on the `augmentedScopeContextsNoCfg` NULL pass
  (`hostConfigScopeIds = {}`) + `drainedForHostConfigs`, never the main augmented contexts; §A
  comment block verbatim.

## Known theoretical edge (documented, not exercised)
An `osConfig`-only (not `config`) collected emit with NO `config`-thunk anywhere would now *resolve*
where it previously *deferred* (the resolve.nix scan predicate is narrower than assemble-pipes'
`isConfigDependent`, and `hostConfigScopeIds` is non-empty whenever host-output scopes exist).
**Not hit by any of the 1052 tests nor by real axon** (byte-identical) ⇒ theoretical. Resolving is
the more-consistent behavior and matches the `== {}` design intent. If it ever surfaces, the hola
O(K) parity gate is the backstop.

## Footgun status
S1 does NOT reduce an already-correct matched-peer cost (Gate-A laziness handled that). Its win is
**removing the latent fleet-wide arming** (a config-dep thunk's mere presence no longer constructs
`specsByHost`/forces peer configs) and **keeping closed paths zero-cost** (the `anyConfigDepThunk`
guard). Validated by the new fixtures (throwing peer not built unless matched) + closed-path no-regression.

## Open decision (D5)
S1 is a clean, focused, mergeable den diff (touches only the fx seam the fix-branch parent does not).
**Default = HOLD on `feat/s1-per-sid-hostconfig`** pending the den-hoag seam decision (§8a D5: ship
S1 standalone to denful/den, or fold into den-hoag). Surfaced to the user. NOT pushed.

## Verdict: COMPLETE
Byte-identical on synth + real axon, den CI green (+2 fixtures), the latent footgun removed without
behavior change. Next: S2 (the unscoped-`collectAll`+config-dep lint = footgun guard; cone-expander
`pipe.reads` is lower-value/base-dominated per the §8a grounding).
