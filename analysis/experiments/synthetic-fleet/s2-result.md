# Fleet seam S2 — result (2026-06-28)

`plans/2026-06-28-fleet-seam-s2-pipe-reads-cone-lint.md`. `pipe.reads [paths]` cone-expander +
the unscoped-`collect`/`collectAll` config-dep **lint**. den commit `487cc671` on `feat/s2-pipe-reads`
(stacked on S1 `b3449c8b`; den worktree, NOT pushed; held with S1 pending §8a-D5).

## The change
- `nix/lib/policy-effects.nix` — `pipe.reads = paths: { __pipeStage = "reads"; inherit paths; }`
  (list-of-strings validated). Declares an open emit's config cone.
- `nix/lib/aspects/fx/assemble-pipes.nix` —
  - `coneView cfg paths` = a peer-config view holding ONLY the declared dotted paths' real (lazy)
    values (`foldl'` of `setAttrByPath (getAttrFromPath …)`); undeclared fields are simply absent ⇒
    a read outside the cone throws Nix's natural "attribute missing". A declared config-dep emit
    resolves against `coneView (hostConfigFor sid) paths` instead of the full peer config. Threaded
    as `coneInfo = { paths; stage; pipeName; }` through `resolveThunks`/`resolveEntry` (collect/
    collectAll) + `collectAllBroadcast` (broadcast).
  - **The lint** fires in `resolveEntry`'s `isConfigDependent` branch when `coneInfo.paths == null`
    — i.e. a config-dependent cross-scope (collect/collectAll/broadcast) emit with no `reads` stage.
    Local config-dep emits go through `markConfigThunk` (never `resolveThunks`) so are untouched;
    closed/pipeline-parametric emits never reach the branch.

## Honest framing (do not over-sell — measured grounding)
The cone is **ENFORCEMENT**, not a runtime copies cut: Nix laziness already scopes the open read to
the fields touched (step-1: an open read forced 8.3% of toplevel copies), and the cone is base-
dominated. `pipe.reads`'s value = (a) the **lint** (the keeper — forbids the unscoped fleet-wide
blow-up), and (b) an honest, bounded cone declaration for the downstream uses (affected-set, class-
share, blast-radius). An out-of-cone read fails loud, so the declaration is trustworthy.

## Validation — byte-identical, lint proven on a real emit
- **den CI:** `1054/1054` (clean S2 worktree == S1) → **`1057/1057`** (1054 unchanged + 3 new S2
  deadbugs tests). The new lint required den's own config-dep COLLECTED fixtures to declare `reads`;
  updated (byte-identical resolved output, only the policy source gains a declaration):
  `bprime-basedrain-crosshost` (2), `s1-per-sid-hostconfig-laziness` (1), `public-api/pipe-scope` (3),
  `public-api/pipe-broadcast` (2), `templates/fleet-demo/.../pipes.nix` (1).
- **Lint proven on a REAL open emit (stronger than a synth fixture):** evaluating the nix-config
  demo-branch with the S2 override threw, verbatim:
  `den: pipe.collect: open (config-dependent) cross-host emit "persist-claims" must declare its read
  cone with pipe.reads [ … ] (the unscoped form forces every peer's full config). Add a pipe.reads
  stage.` — the lint caught the actual step-1 demo emit.
- **Full S2 loop, byte-identical:** adding `(pipe.reads [ "users.users" ])` to the persist-claims
  collect (it reads peer `config.users.users.frr.uid`) → resolves **cone-restricted** → `axon-02`
  and `axon-03` `…toplevel.drvPath` **byte-identical to the original pin** (`m88glzsg…`, `9y1dmyp4…`).
  The cone changes nothing about the resolved value; it only bounds + enforces the declaration.
- **Synth fleet:** `classKey` N=10 byte-identical S2 vs pin.
- **Three den-fixture confirmations** (`deadbugs/s2-pipe-reads-cone-lint.nix`, nix-unit 3/3):
  lint rejects config-dep `collectAll`-without-reads (the `synthOpenTrigger`/`globalTrigger` shape);
  a reads-declared emit resolves byte-identically; an out-of-cone read throws.

## Plumbing note (accepted)
An out-of-cone read throws Nix's natural attribute-missing error, which `builtins.tryEval` CANNOT
catch (no in-eval attribute-access interception without enumerating/forcing the peer key structure —
which would break the laziness/base-dominated framing). So the teeth test asserts via the harness's
`expectedError = { type = "EvalError"; msg = "hostName"; }` (nix-unit). The LINT itself uses `throw`
(tryEval-catchable). `coneInfo` is carried alongside the collect predicate (`readsConeOf stages`);
lint + cone fire at the single config-dep resolution site in `resolveEntry`.

## Verdict: COMPLETE
den CI green (+3 fixtures), real-axon + synth byte-identical, the lint proven on the real
`persist-claims` open emit + the full declare→resolve→identical loop demonstrated. The lint is the
measured-high-value piece (forbids the unscoped blow-up); the cone is honest enforcement, not an
over-claimed runtime saving.

**This completes the open-emit-affordability band (Plane-2a + S1 + S2).** Remaining is explicitly
beyond the band: the den-hoag inject-at-`instantiate` seam itself (§8a, a separate program — where
Plane-2a's identified saving gets *realized* in production), and the Plane-2b cross-invocation
keystone (gen-rebuild content-addressed persistence, deferred).
