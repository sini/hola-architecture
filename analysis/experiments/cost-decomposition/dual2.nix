{ n ? 50, ndecls ? 20, layers ? 1 }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList mkMerge;
  subOptions = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = mkOption { type = types.str; default = "d${toString i}"; };
  }) ndecls);
  subModule = { ... }: { options = subOptions; };
  # REAL merge: each layer sets a DISTINCT option (coexisting defs reaching type.merge per-option,
  # AND each element gets `layers` separately-merged options forced).
  elemVal = i: mkMerge (genList (l:
    { "opt${toString l}" = "v${toString i}.${toString l}"; }
  ) layers);
  eval = evalModules {
    modules = [
      { options.things = mkOption { type = types.attrsOf (types.submodule subModule); default = {}; }; }
      { config.things = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = elemVal i; }) n); }
    ];
  };
  # force ALL ndecls options of each element (not just opt0) to actually exercise per-option merge
  forceAll = lib.mapAttrs (k: v: lib.mapAttrs (ok: ov: ov) v) eval.config.things;
in
  builtins.deepSeq forceAll (builtins.attrNames eval.config.things)
