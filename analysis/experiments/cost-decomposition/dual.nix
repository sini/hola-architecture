{ n ? 50, ndecls ? 20, layers ? 1 }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList mkMerge mkDefault;
  subOptions = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = mkOption { type = types.str; default = "d${toString i}"; };
  }) ndecls);
  subModule = { ... }: { options = subOptions; };
  # each element value = mkMerge of `layers` layers, each setting opt0 with a
  # priority so they merge under filterOverrides/sortProperties (value-merge work)
  elemVal = i: mkMerge (genList (l:
    { opt0 = lib.mkOverride (100 - l) "v${toString i}.${toString l}"; }
  ) layers);
  eval = evalModules {
    modules = [
      { options.things = mkOption { type = types.attrsOf (types.submodule subModule); default = {}; }; }
      { config.things = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = elemVal i; }) n); }
    ];
  };
in
  builtins.deepSeq (lib.mapAttrs (k: v: v) eval.config.things) (builtins.attrNames eval.config.things)
