{ N, B, withDefault }:
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  mkBaseOpts = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = if withDefault
      then mkOption { type = types.str; default = "d${toString i}"; }
      else mkOption { type = types.str; };   # NO default
  }) B);
  submoduleType = types.submodule { options = mkBaseOpts; };
  # If no default, every option MUST be set -> set all B with single def (fast path eligible).
  elements = builtins.listToAttrs (genList (i: {
    name = "e${toString i}";
    value = builtins.listToAttrs (genList (j: { name = "opt${toString j}"; value = "v${toString i}_${toString j}"; }) B);
  }) N);
  result = evalModules {
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = elements; }
    ];
  };
in builtins.deepSeq result.config.svc "OK"
