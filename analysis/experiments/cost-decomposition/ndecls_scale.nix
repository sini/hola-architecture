# Vary ndecls (declared options in submodule) holding config defs constant (1 def on opt0).
# This scales declsByName shape transpose. Per-element marginal cost vs ndecls reveals
# how much per-element cost is SHAPE (hoistable, decl-driven) vs fixed.
{ n ? 1, ndecls ? 20 }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList;
  subOptions = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = mkOption { type = types.str; default = "d${toString i}"; };
  }) ndecls);
  sub = { ... }: { options = subOptions; };
  eval = evalModules {
    modules = [
      { options.things = mkOption { type = types.attrsOf (types.submodule sub); default = {}; }; }
      { config.things = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "v${toString i}"; }; }) n); }
    ];
  };
in
  builtins.deepSeq (lib.mapAttrs (k: v: v) eval.config.things) (builtins.attrNames eval.config.things)
