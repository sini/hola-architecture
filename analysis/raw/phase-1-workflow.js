export const meta = {
  name: 'hoag-nixpkgs-feasibility',
  description: 'Investigate whether a gen/HOAG module engine can keep nixpkgs compat but cut evalModules cost',
  phases: [
    { title: 'Anatomy', detail: 'parallel deep-readers: nixpkgs modules, types, adios, evaluator, gen, HOAG' },
    { title: 'Synthesize', detail: 'unified cost model + candidate techniques + load-bearing claims' },
    { title: 'Verify', detail: 'adversarially refute each load-bearing claim via 3 diverse lenses' },
  ],
}

const CTX = `PROJECT GOAL: design a NEW flake/module framework built ON the gen ecosystem — a HOAG-based alternative to adios (github:adisbladis/adios) and adios-flake — that, UNLIKE adios, does NOT replace the NixOS module system with a smaller one. Instead it aims to RETAIN full nixpkgs/NixOS module compatibility and content while optimizing Nix evaluation/laziness so it avoids paying the NixOS module system's full machinery cost. Separate from the 'den' project but reusing gen primitives.
REPOS (verify paths before reading): nixpkgs=~/Documents/repos/nixpkgs ; adios=~/Documents/repos/adios ; adios-flake=~/Documents/repos/adios-flake ; gen=~/Documents/repos/gen ; den=~/Documents/repos/den ; den specs=~/Documents/papers/den-architecture .
STYLE: compressed prose, FULL technical precision, cite file:line. Read real source, not memory.`

const READER_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['area', 'costCenters', 'keyFindings', 'hardClaims', 'openQuestions'],
  properties: {
    area: { type: 'string' },
    costCenters: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['name', 'whatItCosts', 'eagerOrLazy', 'avoidable', 'fileRefs'],
        properties: {
          name: { type: 'string' },
          whatItCosts: { type: 'string' },
          eagerOrLazy: { type: 'string', description: 'eager | lazy | mixed, with the demand condition' },
          avoidable: { type: 'string', enum: ['intrinsic', 'machinery', 'mixed'] },
          fileRefs: { type: 'array', items: { type: 'string' } },
        },
      },
    },
    lazinessBoundaries: { type: 'array', items: { type: 'string' } },
    keyFindings: { type: 'array', items: { type: 'string' } },
    hardClaims: { type: 'array', items: { type: 'string' }, description: 'load-bearing factual claims you are confident in' },
    openQuestions: { type: 'array', items: { type: 'string' } },
  },
}

const SYNTH_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['costModel', 'intrinsicVsMachinery', 'candidates', 'hardClaims'],
  properties: {
    costModel: { type: 'string', description: 'ranked narrative: where NixOS module eval spends, eager vs lazy' },
    intrinsicVsMachinery: { type: 'string', description: 'sharp separation of unavoidable nixpkgs-content cost vs avoidable module-machinery cost' },
    candidates: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'name', 'thesis', 'mechanism', 'keepsCompat', 'targets', 'expectedSaving', 'risk'],
        properties: {
          id: { type: 'string' },
          name: { type: 'string' },
          thesis: { type: 'string' },
          mechanism: { type: 'string' },
          keepsCompat: { type: 'string', enum: ['full', 'partial', 'none'] },
          targets: { type: 'array', items: { type: 'string' } },
          expectedSaving: { type: 'string' },
          risk: { type: 'string' },
        },
      },
    },
    hardClaims: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'claim', 'whyLoadBearing'],
        properties: {
          id: { type: 'string' },
          claim: { type: 'string', description: 'falsifiable statement' },
          whyLoadBearing: { type: 'string' },
        },
      },
    },
  },
}

const CLAIM_VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['claimId', 'lens', 'refuted', 'nuance', 'evidence'],
  properties: {
    claimId: { type: 'string' },
    lens: { type: 'string' },
    refuted: { type: 'boolean' },
    nuance: { type: 'string' },
    evidence: { type: 'string' },
  },
}

// ---- Phase A: Anatomy ----
phase('Anatomy')

const readers = [
  {
    label: 'nixos-modules',
    prompt: `${CTX}

TASK: Deep-read the NixOS module system to map evaluation cost. Primary file: ~/Documents/repos/nixpkgs/lib/modules.nix.
Trace: evalModules -> mergeModules -> mergeModules' -> mergeDefinitions; also unifyModuleSyntax, applyModuleArgsIfFunction, filterOverrides, sortProperties, defaultPrioFunctions/mkMerge/mkIf/mkOverride/mkForce handling, the _module options + _module.args, specialArgs threading, and exactly how 'config' and 'options' form a single recursive fixpoint.
For each cost center determine: (a) forced EAGERLY during any evalModules call regardless of which config attrs the caller reads, or DEFERRED until a specific option is demanded? (b) where do '//' attrset copies and large list concats happen? (c) what forces the SHAPE of the option tree (attrNames-level) vs the VALUES?
CRITICAL QUESTION to answer with evidence: can the global config fixpoint be partitioned into independent sub-fixpoints, or does any module's ability to define ANY option (and read any other via the shared config) entangle the whole thing? What about \`config\`-dependent \`imports\` (imports computed from config)?
Cite file:line throughout.`,
  },
  {
    label: 'nixos-types',
    prompt: `${CTX}

TASK: Deep-read ~/Documents/repos/nixpkgs/lib/types.nix for evaluation cost and laziness.
For each major type (submodule, submoduleWith, attrsOf, lazyAttrsOf, listOf, attrTag, oneOf, either, nullOr, enum, str/int/path, functionTo) state EXACTLY when its \`merge\` and \`check\` force values, and whether it preserves or defeats laziness.
Focus: submodule = recursive evalModules (the cost multiplier — quantify how submodule nesting compounds); the lazyAttrsOf vs attrsOf laziness difference and why it exists; how listOf/attrsOf force element structure; \`check\` cost; coercedTo.
Identify which type usages dominate real NixOS config cost (e.g. systemd.services as attrsOf submodule). Cite file:line.`,
  },
  {
    label: 'adios-engine',
    prompt: `${CTX}

TASK: Deep-read ~/Documents/repos/adios/adios/default.nix and ~/Documents/repos/adios/adios/lib/importModules.nix.
Precisely document the incremental memoization engine: resolveTree (forward genericClosure), evalModuleTree (args/results fixpoint via rec), mkOverride (the reverse genericClosure 'diff', memoArgs/memoResults removeAttrs), applyTreeOptions / computeArgs / the __functor re-compute path, getModule path resolution.
State exactly: WHAT is memoized and at what granularity; WHAT makes override cheap; and WHAT compatibility adios SACRIFICES vs the NixOS module system — specifically: priorities/mkMerge/mkIf/mkForce? multi-producer merge of one option? global \`config\` visibility (any module reading any option)? imports computed from config? option doc generation? type-checked merges?
Then the KEY assessment: if you fed real NixOS modules (that read a shared config fixpoint and use mkMerge/mkIf and attrsOf-submodule) into an adios-style engine, what breaks and why? Is adios's explicit-edge + isolated-per-module-result model fundamentally incompatible with NixOS's shared-fixpoint-write model, or bridgeable? Cite file:line.`,
  },
  {
    label: 'nix-evaluator',
    prompt: `${CTX}

TASK: Map the Nix evaluator performance model as it pertains to the module system, and settle two pivotal questions.
Explain what each NIX_SHOW_STATS metric means (function calls, prim ops, thunks created, attr lookups, attrset updates, values copied via //, GC heap) and what SOURCE PATTERNS generate each. Explain attrset \`//\` copy semantics + sharing, thunk forcing, how attrNames/mapAttrs/foldl'/genericClosure interact with laziness, and what DEFEATS laziness (deepSeq, seq, structural attrNames over a merged set, builtins.toJSON).
PIVOTAL Q1: Is cross-evaluation memoization possible in PURE Nix — i.e. sharing computed results between two otherwise-independent evalModules invocations — or is only intra-eval thunk sharing available (and what exactly enables adios's sharing — same root tree object + override)?
PIVOTAL Q2: Can a module's option read-set (which config.* paths it reads) be discovered WITHOUT evaluating it? Nix has builtins.functionArgs but no function-body reflection. Assess pure-Nix (impossible?) vs EXTERNAL static analysis (parsing .nix files / nix-instantiate --parse / a tree-sitter pass) as a separate architectural path, including soundness under dynamism (config.\${var}, computed attr names, with).
Reference ~/Documents/repos/adios-flake/BENCHMARKS.md numbers and state precisely what they prove and DON'T prove (note values-copied is ~unchanged). Cite where you can.`,
  },
  {
    label: 'gen-primitives',
    prompt: `${CTX}

TASK: Inventory the gen ecosystem for primitives reusable in a new, faster, graph-aware module engine. Read ~/Documents/repos/gen (TERMINOLOGY.md, ARCHITECTURE.md, README.md) then the library sources.
For gen-derive, gen-schema, gen-aspects, gen-select, gen-algebra, gen-bind: state what each provides and MAP it to a module-system concern — merge/conflict-resolution (vs NixOS mergeDefinitions + priority machinery), type/option registries (vs lib/types + options), stratified dispatch, layered settings precedence (gen-algebra foldLayersTraced vs mkMerge/mkOverride ordering), graph/edge structures, schema entities/registries.
Identify which gen primitives could DIRECTLY implement parts of the new engine (e.g. could gen-derive replace mergeDefinitions? could gen-schema model the option tree? could gen-algebra's layered fold replace priority resolution?), and the GAPS that remain. Verify paths exist; cite source files.`,
  },
  {
    label: 'hoag-graph',
    prompt: `${CTX}

TASK: Document HOAG and den's scope-engine as an OPTION-GRAPH model, aimed at the feasibility question.
Read ~/Documents/papers/den-architecture (HOAG spec; the edge-algebra with S/T/P/M; neededBy; spawn/edge/drop/reroute/inject vocabulary) and relevant den source at ~/Documents/repos/den (scope-engine / fx-pipeline / resolver).
Explain: what graph HOAG builds, what its edges/attributes mean, and what incrementality the EXPLICIT edges enable (contrast with NixOS's implicit-via-shared-config dependencies).
Then map onto the central question: could HOAG's edge model partition an option/config graph into independently-evaluable regions connected by explicit typed edges — giving adios-style incremental override — WHILE still hosting real nixpkgs modules? What does HOAG already solve that the NixOS module system does not? What would HOAG need to ADD to be compat-preserving (host unmodified nixpkgs modules)? Include den's hard-won eval-cost lessons (eager eval, manual context threading, eval cycles, deepSeq state).`,
  },
]

const findings = (await parallel(
  readers.map(r => () => agent(r.prompt, { label: r.label, phase: 'Anatomy', schema: READER_SCHEMA }))
)).filter(Boolean)

log(`Anatomy complete: ${findings.length}/${readers.length} reports`)

// ---- Phase B: Synthesize ----
phase('Synthesize')

const synth = await agent(`${CTX}

You are synthesizing a rigorous feasibility investigation. CENTRAL QUESTION: can we build a new gen/HOAG-based flake+module framework that RETAINS full nixpkgs/NixOS module compatibility and content, yet optimizes Nix evaluation/laziness to avoid paying the NixOS module system's full machinery cost — INSTEAD of adios's strategy of replacing it with a smaller system?

Below are six grounded, source-cited investigation reports (JSON array):
${JSON.stringify(findings)}

Produce, per the schema:
1. costModel — a RANKED narrative of where NixOS module eval actually spends time, eager vs lazy, grounded in the reports.
2. intrinsicVsMachinery — sharply separate costs INTRINSIC to nixpkgs *content* (unavoidable while keeping compat — e.g. nixpkgs import, the // copy storm the benchmarks show is ~unchanged) from costs of the module-system *machinery* (potentially avoidable — evalModules merge/priority resolution/type-checking/doc-gen/_module plumbing). This separation IS the answer to the feasibility question — be precise about the size of the avoidable slice.
3. candidates — EVERY concrete technique to keep-nixpkgs-but-pay-less that the evidence supports. Consider at least: memoize the system-independent module prefix; lazy-splice merge instead of // copies; partition the config fixpoint via explicit HOAG edges; an evalModules-lite drop-in that drops doc-gen/checks/rarely-used-priority paths; opt-in edge-annotated incremental modules with full-eval fallback; external static edge discovery (parse .nix); coarse-grain per-host / per-flake-input evalModules memoization; gen-derive as a mergeDefinitions replacement; submodule-eval deferral. For EACH: thesis, mechanism, keepsCompat (full|partial|none), which cost center it targets, expected saving, risk. Invent additional candidates the evidence justifies.
4. hardClaims — the LOAD-BEARING factual claims the feasibility verdict rests on, each phrased as a single FALSIFIABLE statement (e.g. about fixpoint partitionability, edge discoverability, soundness of prefix memoization, the size of the avoidable cost slice). 4-7 claims.

Be rigorous and HONEST; flag where the reports conflict or are uncertain. Do not overclaim. Compressed prose, full technical precision.`, { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA })

log(`Synthesis: ${synth.candidates.length} candidates, ${synth.hardClaims.length} load-bearing claims`)

// ---- Phase C: Verify load-bearing claims ----
phase('Verify')

const lenses = ['nixpkgs-source-reality', 'eval-semantics-soundness', 'implementation-realism']

const claimVerdicts = await parallel(synth.hardClaims.map(c => () =>
  parallel(lenses.map(lens => () =>
    agent(`${CTX}

Adversarially evaluate ONE load-bearing claim from a feasibility study on building a nixpkgs-COMPATIBLE, gen/HOAG-based module engine.

CLAIM (id=${c.id}): "${c.claim}"
WHY IT MATTERS: ${c.whyLoadBearing}

Examine it strictly through the **${lens}** lens. Your job is to REFUTE it if at all possible — find the counterexample in nixpkgs source, the eval-semantics edge case, or the implementation reality that makes the claim false or materially overstated. Ground in actual source (~/Documents/repos/nixpkgs, ~/Documents/repos/adios). Default to refuted=true if you find genuine doubt; only uphold (refuted=false) if the claim survives a real attack. Give concrete evidence (file:line where possible) and the nuance/conditions under which it holds or fails.`,
      { label: `verify:${c.id}:${lens}`, phase: 'Verify', schema: CLAIM_VERDICT_SCHEMA })
  )).then(vs => ({ claim: c, verdicts: vs.filter(Boolean) }))
))

return {
  costModel: synth.costModel,
  intrinsicVsMachinery: synth.intrinsicVsMachinery,
  candidates: synth.candidates,
  claimVerdicts: claimVerdicts.filter(Boolean),
}
