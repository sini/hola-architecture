# Same submodule with ndecls options, but force ONLY opt0 per element (not all options).
# If per-elem cost still scales with ndecls -> shape is EAGER (hoistable-relevant).
# If per-elem cost flattens -> the ndecls scaling was per-option MERGE (demand-driven, NOT pure re-collection).
{ n ? 1, ndecls ? 20, forceAll ? false }:
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
  things = eval.config.things;
in
  if forceAll
  then builtins.deepSeq (lib.mapAttrs (k: v: v) things) (builtins.attrNames things)
  else builtins.deepSeq (lib.mapAttrs (k: v: v.opt0) things) (builtins.attrNames things)
