{ N, B }:
# Simulate a SHARED-SHAPE engine: collect the base option tree ONCE, then for
# each element merge its config against the pre-collected option set, evaluating
# each option's value with the shared declaration. This is the THEORETICAL FLOOR
# of HC2's win - no per-element re-collection.
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList mergeDefinitions evalOptionValue;
  # Base option declarations, collected ONCE.
  baseModule = { options = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}"; value = mkOption { type = types.str; default = "d${toString i}"; };
  }) B); };
  shared = evalModules { modules = [ baseModule ]; };
  sharedOpts = shared.options;  # collected ONCE
  elements = genList (i: { opt0 = "v${toString i}"; }) N;
  # Per element: bind config to the SHARED option declarations via evalOptionValue.
  evalEl = cfg: lib.mapAttrs (name: opt:
    (evalOptionValue [ name ] opt (
      lib.optional (cfg ? ${name}) { file = "el"; value = cfg.${name}; }
    )).value
  ) (removeAttrs sharedOpts [ "_module" ]);
in builtins.deepSeq (map evalEl elements) "OK"
