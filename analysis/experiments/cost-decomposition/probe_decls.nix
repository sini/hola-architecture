{ n ? 50, ndecls ? 20, mode ? "default" }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList;
  # mode = "default": each swept opt has a string default (override-wrapped, slow path on unset)
  # mode = "empty":   each swept opt is types.attrs with emptyValue, NO default => isDefined=false, no merge
  # opt0 is always a set str option (the realistic single-def element value).
  mkSub = i:
    if i == 0 then mkOption { type = types.str; default = "d0"; }
    else if mode == "default" then mkOption { type = types.str; default = "d${toString i}"; }
    else mkOption { type = types.attrs; };  # emptyValue {}, no default
  subOptions = builtins.listToAttrs (genList (i: { name = "opt${toString i}"; value = mkSub i; }) ndecls);
  subModule = { ... }: { options = subOptions; };
  eval = evalModules {
    modules = [
      { options.things = mkOption { type = types.attrsOf (types.submodule subModule); default = {}; }; }
      { config.things = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "v${toString i}"; }; }) n); }
    ];
  };
in
  builtins.deepSeq (lib.mapAttrs (k: v: v) eval.config.things) (builtins.attrNames eval.config.things)
