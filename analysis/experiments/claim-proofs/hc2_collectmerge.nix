{ N, B, force }:
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  baseModule = { options = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}"; value = mkOption { type = types.str; default = "d${toString i}"; };
  }) B); };
  submoduleType = types.submodule baseModule;
  elements = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "v${toString i}"; }; }) N);
  r = evalModules { modules = [
    { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
    { config.svc = elements; } ]; };
in
  if force == "options"
  # Force only the option SHAPE of each element (getSubOptions / declarations) -
  # this is the part a sharing engine could amortize.
  then builtins.deepSeq (lib.mapAttrs (n: v: builtins.attrNames v) r.options.svc) "OPTS"
  else builtins.deepSeq r.config.svc "CONFIG"
