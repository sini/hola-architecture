# Verify the shared-shape engine produces values IDENTICAL to vanilla submodule.
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList evalOptionValue;
  B = 4; N = 3;
  baseModule = { options = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}"; value = mkOption { type = types.str; default = "d${toString i}"; };
  }) B); };
  # Vanilla
  submoduleType = types.submodule baseModule;
  elements = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "set${toString i}"; }; }) N);
  vanilla = evalModules { modules = [
    { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
    { config.svc = elements; } ]; };
  # Shared-shape
  shared = (evalModules { modules = [ baseModule ]; }).options;
  shapedEval = cfg: lib.mapAttrs (name: opt:
    (evalOptionValue [ name ] opt (lib.optional (cfg ? ${name}) { file = "el"; value = cfg.${name}; })).value
  ) (removeAttrs shared [ "_module" ]);
in {
  vanilla_e0 = vanilla.config.svc.e0;
  shaped_e0  = shapedEval { opt0 = "set0"; };
  equal = (vanilla.config.svc.e0 == shapedEval { opt0 = "set0"; });
}
