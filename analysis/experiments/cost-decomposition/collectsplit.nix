# Isolate element-independent collect (import/functionArgs/unify) from element-dependent
# re-application (applyModuleArgs binding config/name). Two submodule shapes:
#  - "fn": submodule defined as a FUNCTION ({name,...}: {options=...}) -> applyModuleArgs runs per element
#  - "attr": submodule defined as a bare ATTRSET ({options=...}) -> no function application per element
{ n ? 1, mode ? "fn" }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList;
  subOptions = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = mkOption { type = types.str; default = "d${toString i}"; };
  }) 20);
  subModuleFn   = { name, ... }: { options = subOptions; };
  subModuleAttr = { options = subOptions; };
  sub = if mode == "fn" then subModuleFn else subModuleAttr;
  eval = evalModules {
    modules = [
      { options.things = mkOption { type = types.attrsOf (types.submodule sub); default = {}; }; }
      { config.things = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "v${toString i}"; }; }) n); }
    ];
  };
in
  builtins.deepSeq (lib.mapAttrs (k: v: v) eval.config.things) (builtins.attrNames eval.config.things)
