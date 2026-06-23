{ N, B, override }:
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  mkBaseOpts = prefix:
    builtins.listToAttrs (genList (i: {
      name = "${prefix}${toString i}";
      value = mkOption { type = types.str; default = "d${toString i}"; };
    }) B);
  submoduleType = types.submodule ({ name, ... }: { options = mkBaseOpts "opt"; });
  elements = builtins.listToAttrs (genList (i: {
    name = "e${toString i}";
    value = builtins.listToAttrs (genList (j: {
      name = "opt${toString j}"; value = "v${toString i}_${toString j}";
    }) override);
  }) N);
  result = evalModules {
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = elements; }
    ];
  };
in builtins.deepSeq result.config.svc "OK"
