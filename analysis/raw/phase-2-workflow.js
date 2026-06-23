export const meta = {
  name: 'hola-full-hoag-evaluation',
  description: 'What a full HOAG reimplementation of nixpkgs module eval (custom evalModules) meaningfully changes vs the orchestrate-around verdict; incl. literature-grounded new gen modules',
  phases: [
    { title: 'ReTier', detail: 'parallel readers: cost re-tiering, parity surface, lib-injection seam, runtime read-capture, HOAG option-graph, prior art, literature->gen-extensions' },
    { title: 'Synthesize', detail: 'what changes vs Phase 1 + re-tiered cost + parity verdict + residual floor + new candidates + claims' },
    { title: 'Verify', detail: 'adversarially refute each expanded-scope load-bearing claim via 3 diverse lenses' },
  ],
}

const CTX = `PROJECT: 'hola' — a new flake+module framework on the gen ecosystem + den HOAG edge model that hosts UNMODIFIED nixpkgs/NixOS modules but evaluates faster than lib.evalModules+flake-parts.
EXPANDED SCOPE (this study): UNLIKE Phase 1, do NOT assume lib.evalModules is retained verbatim. Assume hola REIMPLEMENTS module evaluation itself — a custom, lazy, HOAG-structured evalModules that is SEMANTICALLY compatible with nixpkgs modules (hosts them unmodified), plus a module-free gen introspection plane and shims that inject the custom engine WITHOUT forking nixpkgs. We control gen-schema/gen-aspects and can change their deferredModule contract. We MAY ALSO extend gen with NEW modules/primitives where hola core papers or other existing literature justify it (do NOT assume only existing gen libs are available). Question: what does a FULL HOAG nixpkgs evaluation meaningfully CHANGE vs Phase 1 'orchestrate around verbatim lib.evalModules' verdict?

PHASE 1 ESTABLISHED (build on this; extend/challenge under expanded scope, do NOT re-derive):
COST CENTERS of nixpkgs module eval: (A) EAGER phase-1 SHAPE construction — mergeModules' zipAttrs transpose of declsByName/pushedDownDefinitionsByName, O(#modules x #option-paths), eager regardless of which config attr is read (modules.nix:275,789-852). (B) EAGER _module.check unmatchedDefns full attrName walk, skippable via check=false/freeformType (modules.nix:304-376). (C) LAZY per-option value merge, demand-scaled, fast-path for single-def (modules.nix:1185-1311,1214-1235). (D) LAZY-but-MULTIPLICATIVE submodule recursion — one fresh evalModules per attrsOf/listOf-submodule element via base.extendModules (types.nix:1452-1455); systemd.services etc; O(NxM). (E) the // copy storm — ~1.85M copies, dominated by nixpkgs import package-set fixpoint (fixed-points.nix:333 extends), NOT module machinery.
VERIFIED FLOORS (all survived 3-lens adversarial attack): H1 the // storm is INTRINSIC (abandoning the module system moves it -0.3%; ~1,756,268 copies just to import<nixpkgs> force attrNames, +99 for evalModules). H2 only the composition/multi-system axis is MEASURED to speed up (~30%); per-host evalModules unmeasured/unreduced UNDER VERBATIM lib. H3 single evalModules level has a flat non-statically-partitionable option namespace; only clean boundary is the submodule (nested evalModules). H4 module config.* read-set NOT statically recoverable (functionArgs name-only; dynamic selects config.x.DOLLAR{k}, doRename aliasing, with). H5 gen-schema/gen-aspects built ON lib.types.deferredModule, force lib.evalModules on introspection (entry-type.nix:32,:223) — BUT the parent/collection graph plane is already module-free (entry-type.nix:89-97); only ref/option introspection forces evalModules. H6 helpful memo is INTRA-eval thunk sharing only; pure Nix cannot persist a forced thunk across nix-eval invocations. H7 retaining nixpkgs option CONTENT forces merge SEMANTICS (mkOverride/mkIf/mkOrder/type.merge) to run somewhere — NO current gen primitive replicates it (foldLayers is priority-blind/position-driven; gen-derive resolves which RULES fire not value merge) — but the irreducible KERNEL is the typed option-tree fixpoint walk + merge algebra AT CONFLICT SITES; single-def leaves hit a ~free fast path.
THE REFRAME THIS STUDY TESTS: Phase 1 drew intrinsic-vs-machinery assuming lib.evalModules RETAINED. A custom engine moves A,B,D from intrinsic to attackable (merge SEMANTICS intrinsic, merge IMPLEMENTATION is machinery). Only H1 stays a hard floor regardless. Phase 1 report at ~/Documents/papers/hola-architecture/analysis/phase-1-feasibility.md.

REPOS (verify paths): nixpkgs=~/Documents/repos/nixpkgs ; adios=~/Documents/repos/adios ; adios-flake=~/Documents/repos/adios-flake ; gen=~/Documents/repos/gen ; den=~/Documents/repos/den ; papers=~/Documents/papers/den-architecture (reference-catalog + used/summaries hold the core papers).
STYLE: compressed prose, FULL technical precision, cite file:line / URL. Read real source. Run NIX_SHOW_STATS / nix-instantiate experiments where they settle a number. Note DOLLAR{x} in this brief denotes a literal Nix interpolation, not a JS one.`

const READER_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['area', 'findings', 'whatChangesUnderCustomEngine', 'hardClaims', 'openQuestions'],
  properties: {
    area: { type: 'string' },
    findings: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['point', 'evidence', 'fileRefs'],
      properties: { point: { type: 'string' }, evidence: { type: 'string' }, fileRefs: { type: 'array', items: { type: 'string' } } } } },
    whatChangesUnderCustomEngine: { type: 'array', items: { type: 'string' } },
    hardClaims: { type: 'array', items: { type: 'string' } },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const SYNTH_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['reTieredCostModel', 'whatChanges', 'parityVerdict', 'hardFloor', 'candidates', 'hardClaims'],
  properties: {
    reTieredCostModel: { type: 'string' },
    whatChanges: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['item', 'phase1Said', 'expandedScopeChangesItTo', 'magnitude', 'confidence'],
      properties: {
        item: { type: 'string' }, phase1Said: { type: 'string' }, expandedScopeChangesItTo: { type: 'string' },
        magnitude: { type: 'string' }, confidence: { type: 'string', enum: ['high', 'medium', 'low'] },
      } } },
    parityVerdict: { type: 'string' },
    hardFloor: { type: 'string' },
    candidates: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['id', 'name', 'thesis', 'mechanism', 'enablesWhat', 'risk'],
      properties: { id: { type: 'string' }, name: { type: 'string' }, thesis: { type: 'string' }, mechanism: { type: 'string' }, enablesWhat: { type: 'string' }, risk: { type: 'string' } } } },
    hardClaims: { type: 'array', items: { type: 'object', additionalProperties: false,
      required: ['id', 'claim', 'whyLoadBearing'],
      properties: { id: { type: 'string' }, claim: { type: 'string' }, whyLoadBearing: { type: 'string' } } } },
  },
}

const CLAIM_VERDICT_SCHEMA = {
  type: 'object', additionalProperties: false,
  required: ['claimId', 'lens', 'refuted', 'nuance', 'evidence'],
  properties: { claimId: { type: 'string' }, lens: { type: 'string' }, refuted: { type: 'boolean' }, nuance: { type: 'string' }, evidence: { type: 'string' } },
}

phase('ReTier')

const readers = [
  { label: 'cost-retier', prompt: CTX + `

TASK: Re-tier the cost model under a custom lazy HOAG engine and QUANTIFY the per-host prize. For each of A/B/C/D/E say whether a custom engine reproducing nixpkgs merge SEMANTICS can attack it, the mechanism, the magnitude.
PRIMARY MEASUREMENT (the gating question): for attrsOf/listOf-(submodule) options (D), how much of the per-element cost is RE-COLLECTION (the per-element extendModules to collectModules to mergeModules' shape rebuild — shared across elements, hoistable) vs VALUE-MERGE (intrinsic per element)? Build an instrumented experiment on a real systemd.services-heavy or users.users-heavy eval (NIX_SHOW_STATS deltas as you scale N; compare 1-unit vs 50-unit; isolate collect vs merge). Report the split WITH NUMBERS.
ALSO: (A) how much of mergeModules' eager declsByName/pushedDownDefinitionsByName transpose could be made demand-driven (build only the read subtree) without breaking unmatched-check/freeform semantics. (B) quantify the _module.check walk. Use the nixpkgs checkout. Distinguish 'measured now' from 'needs the prototype to confirm'.` },

  { label: 'parity-surface', prompt: CTX + `

TASK: Enumerate the FULL semantic-parity surface a custom evalModules must reproduce to host UNMODIFIED nixpkgs/NixOS modules, and rule on tractability. Read lib/modules.nix, lib/types.nix, lib/options.nix exhaustively.
Inventory every behavior with compat weight: priority numerics (mkOverride/mkForce/mkDefault/mkVMOverride/mkOptionDefault), mkIf/mkMerge/mkOrder/mkBefore/mkAfter discharge, type.merge + type.check per-type (submodule/submoduleWith/attrsOf/lazyAttrsOf/listOf/either/oneOf/coercedTo/functionTo/enum), _module.args + specialArgs threading + the config._module.args.NAME indirection, doRename/mkAliasOptionModule/mkRenamedOptionModule/mkAliasAndWrapDefsWithPriority, imports closure + ordering + disabledModules, freeformType, option apply/defaultText/example, assertions/warnings, key/_file provenance for errors, extendModules/specialisation, options-vs-config fixpoint visibility (any module reads any option).
For EACH: frequency/criticality in real nixpkgs (grep counts), reproduction difficulty, catastrophe-if-wrong. VERDICT: is the surface tractable? the MINIMAL compatible subset (80/20 that hosts most real configs)? the LANDMINES (subtle enough to silently mis-evaluate)?` },

  { label: 'lib-injection', prompt: CTX + `

TASK: Establish exactly how a custom evalModules can be INJECTED without forking nixpkgs, and where it leaks. Read nixos/lib/eval-config.nix, flake.nix (nixosSystem / lib.nixosSystem), lib/default.nix, lib/modules.nix (evalModules/evalModulesMinimal entry), lib/types.nix (how submodule/attrsOf reach lib.evalModules).
Determine: (1) does nixosSystem/eval-config thread an overridable lib ALL THE WAY DOWN to the evalModules + types call sites, or are any closed-over/hardcoded so a custom lib.modules.evalModules / lib.types.submoduleWith would NOT be picked up? (2) the EXACT minimal override set to swap the engine (lib.modules.evalModules? lib.evalModules? lib.types.submoduleWith/attrsOf/lazyAttrsOf/deferredModule?). (3) leaks: anything that bypasses the injectable lib (builtins, direct imports of modules.nix, home-manager/nix-darwin entry points). (4) the continuous-parity harness: can you run BOTH the real and custom engine over the same module set in one eval and diff every option — verify feasibility with a small experiment.` },

  { label: 'runtime-capture', prompt: CTX + `

TASK: Assess whether a custom engine can SOUNDLY capture each module's config.* read-set at eval time (adios's explicit edge graph, OBSERVED not predicted) — the capability that unlocks incremental override on vanilla modules (Phase 1 H4 ruled out STATIC discovery; H3 ruled out static partition).
CRITICAL feasibility question: pure Nix has NO attribute-access interception (attrsets are eager-keyed, no getters/proxies). Can read-capture be done in PURE Nix at all? Investigate every angle: (a) a custom-built config where each option is a TRACING thunk (builtins.trace / a writer-style accumulator threaded through the engine) — does forcing it reveal the demanded path set, soundly/completely? (b) two-pass evaluation (observe then use)? (c) builtins.deepSeq / genericClosure probing? (d) does it FUNDAMENTALLY require an instrumented evaluator (Lix/Nix C++ hook, custom builtins) — and is that acceptable for hola (does hola ship its own evaluator / Lix plugin)? Define soundness (never miss a real read) vs completeness (no spurious reads) and overhead. State what incrementality this unlocks (region/host-granular re-eval, adios-style reverse-edge diff) and at what granularity. Reference adios resolveTree/diff (adios/adios/default.nix:245-256,453-469) as the target graph. Run a small Nix experiment if it settles feasibility.` },

  { label: 'hoag-option-graph', prompt: CTX + `

TASK: Define PRECISELY what 'a full HOAG nixpkgs evaluation' means as an eval model, and what graph-structured evaluation buys over nixpkgs's single flat fixpoint. Read the den-architecture HOAG spec (edge-algebra S/T/P/M, neededBy, specificity D<I<P, spawn/edge/drop/reroute/inject) and den scope-engine / gen-scope (lib.fix + co-located _eval memoization).
Answer concretely (mechanism, not hand-waving): (1) in a HOAG reimplementation, what are the NODES (modules? options? option-tree paths?) and EDGES (imports? config reads? option dependencies?)? (2) how does HOAG's edge model express the options/config fixpoint that nixpkgs collapses into one lib.fix — and what does naming edges explicitly buy: lazier forcing? region partitioning? incremental override (reverse-edge closure like adios diff)? (3) map S/T/P/M and specificity D<I<P onto option merge/override precedence — does HOAG's edge algebra SUBSUME mkOverride/mkOrder/mkIf, or only the COMPOSITION around it (which aspects/modules apply to which host)? (4) what can a graph eval do that the flat fixpoint structurally cannot, and what does it COST (graph construction overhead vs the saving)?` },

  { label: 'prior-art', prompt: CTX + `

TASK: Survey prior art — has anyone reimplemented or substantially sped up nixpkgs module evaluation while KEEPING module compatibility (vs the many who REPLACED it)? Use WebSearch and WebFetch (load via ToolSearch with query 'select:WebSearch,WebFetch'). Also read local repos where relevant.
Cover: adios/korora (replaces — confirm), nixus, flake-parts (does NOT touch per-host eval — confirm why), Tvix and its evaluator/module story, Lix evaluator performance work, any fast/lazy evalModules experiments or forks, nixpkgs' OWN modules.nix performance history (type-merge v2 / lazyAttrsOf / laziness improvements, commits/PRs targeting evalModules speed), NixOS RFCs and discourse/GitHub-issue threads on module-system performance, and academic/industry work on incremental/self-adjusting configuration evaluation. For each: what was tried, did it keep compat, did it get faster, why did/didn't it land. Identify the CLOSEST precedent to hola's reimplement-evalModules-keep-compat-go-faster thesis and what it teaches. Cite URLs and commit/PR refs. Be honest where evidence is thin — do NOT fabricate precedents.` },

  { label: 'literature-gen-extensions', prompt: CTX + `

TASK: Mine hola's CORE PAPERS and other existing literature for insights that justify NEW gen modules/primitives a custom HOAG evalModules would need. Read the den-architecture reference-catalog and used/summaries (e.g. tarr-1999 n-degrees-of-separation, lorenzen-2025 first-order-laziness, Palmer, delta-nets / Salvadori interaction-nets, Cardelli) — list what is actually present first.
For each relevant paper: name the technique and whether it founds a NEW gen module the engine needs — specifically:
(a) a literature-grounded TYPE-DRIVEN MERGE ALGEBRA that replicates mkOverride/mkIf/mkOrder/type.merge — the H7 gap NO current gen lib fills. Does any paper (lattice/priority merge, multiple dispatch, n-degrees separation, interaction-net rewriting) give the right algebra? Sketch the gen module (call it e.g. gen-merge) and its laws.
(b) FIRST-ORDER LAZINESS (lorenzen-2025) for demand-driven option-tree construction (cost A) — does it map to a lazy mergeModules?
(c) INCREMENTAL / self-adjusting computation (Adapton, interaction-nets/delta-nets) for runtime-capture incremental override — what gen module would encode the dependency graph + diff?
(d) anything for the HOAG option-graph eval model or for sound dependency capture.
Also use WebSearch/WebFetch (load via ToolSearch) for additional academic literature (incremental computation, lazy attribute grammars, modular type checking / merge lattices) where the local catalog has gaps. Be concrete: paper -> technique -> proposed gen module -> what it buys. HONEST where a paper does NOT actually map — do not force a citation.` },
]

const findings = (await parallel(
  readers.map(r => () => agent(r.prompt, { label: r.label, phase: 'ReTier', schema: READER_SCHEMA }))
)).filter(Boolean)

log('ReTier complete: ' + findings.length + '/' + readers.length + ' reports')

phase('Synthesize')

const synth = await agent(CTX + `

Synthesize the EXPANDED-SCOPE feasibility study. Question: what does a FULL HOAG reimplementation of nixpkgs module evaluation (custom evalModules + module-free gen introspection + lib-injection shims + possibly NEW literature-grounded gen modules, hosting unmodified nixpkgs modules) MEANINGFULLY CHANGE vs Phase 1's 'orchestrate around verbatim lib.evalModules' verdict?

Seven grounded reports (JSON):
` + JSON.stringify(findings) + `

Produce, per schema:
1. reTieredCostModel — A-E re-tiered into still-intrinsic vs now-attackable under a custom engine; QUANTIFY/bound the per-host prize using the cost-retier measurements (the collect-vs-merge split for submodule recursion D is the crux).
2. whatChanges — the structured DELTA vs Phase 1: each item = {item, what Phase 1 said, what the expanded scope changes it to, magnitude (+what must be measured), confidence}. Cover at least: per-host eval winnability (H2 flip?), sound incremental override on vanilla modules (runtime capture), gen introspection going module-free (H5), the merge kernel (H7 narrowed + whether a NEW gen-merge module closes the gap), and anything else the reports surface.
3. parityVerdict — is the semantic-parity surface tractable? the minimal compatible 80/20 subset? the landmines? Is lib-injection + continuous-nix-diff dual-run sufficient to de-risk it?
4. hardFloor — what a full HOAG engine STILL does not change (H1 // storm, merge semantics must run, import-closure forcing, H6 cross-process). Bound the upside HONESTLY.
5. candidates — the NEW techniques the expanded scope enables: demand-driven shape construction, submodule shared-base hoisting, runtime read-capture incremental override, lib-injection parity harness, HOAG region partitioning, module-free gen introspection, AND any NEW literature-grounded gen modules (e.g. gen-merge for type-driven merge, a first-order-laziness primitive, an incremental-computation/delta-net module). thesis/mechanism/enablesWhat/risk each.
6. hardClaims — 5-7 load-bearing FALSIFIABLE statements for the expanded scope (collect-vs-merge split magnitude, runtime-capture feasibility in pure Nix, lib-injection completeness, parity tractability, whether a literature-grounded gen-merge can be byte-identical to lib/types merge).
Rigorous and HONEST; flag conflicts and uncertainty; do not let the exciting reframe inflate confidence past the evidence. Compressed prose, full precision.`, { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA })

log('Synthesis: ' + synth.candidates.length + ' candidates, ' + synth.hardClaims.length + ' claims')

phase('Verify')

const lenses = ['nixpkgs-source-reality', 'eval-semantics-soundness', 'implementation-realism']

const claimVerdicts = await parallel(synth.hardClaims.map(c => () =>
  parallel(lenses.map(lens => () =>
    agent(CTX + `

Adversarially evaluate ONE load-bearing claim from the EXPANDED-SCOPE study (custom HOAG evalModules that hosts unmodified nixpkgs modules).

CLAIM (id=` + c.id + `): "` + c.claim + `"
WHY IT MATTERS: ` + c.whyLoadBearing + `

Examine strictly through the ` + lens + ` lens. REFUTE it if at all possible — the counterexample in nixpkgs source, the eval-semantics edge case, the implementation reality (especially the gap between 'a custom engine COULD' and 'a custom engine CAN soundly + compatibly + with real saving'). Ground in actual source; run a small experiment if it settles the question. Default refuted=true on genuine doubt; uphold only if it survives. Concrete evidence (file:line/URL), and the conditions under which it holds or fails.`,
      { label: 'verify:' + c.id + ':' + lens, phase: 'Verify', schema: CLAIM_VERDICT_SCHEMA })
  )).then(vs => ({ claim: c, verdicts: vs.filter(Boolean) }))
))

return {
  reTieredCostModel: synth.reTieredCostModel,
  whatChanges: synth.whatChanges,
  parityVerdict: synth.parityVerdict,
  hardFloor: synth.hardFloor,
  candidates: synth.candidates,
  claimVerdicts: claimVerdicts.filter(Boolean),
}
