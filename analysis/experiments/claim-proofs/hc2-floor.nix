# Quantify the IRREDUCIBLE per-element floor: even with a perfectly shared base
# shape, each element still pays (1) per-option mergeDefinitions for every
# DEMANDED option, (2) the mkOptionDefault prepend forcing the non-fast-path
# for every option that has a default, (3) the config fixpoint per element.
# Compare: N elements each setting ALL options explicitly (no default prepend
# wins, but length>=2 so fast-path missed) vs N elements setting NONE
# (default-only, length==1 but _type override => fast-path STILL missed).
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) evalModules mkOption types range;
  t = types.submodule {
    options = builtins.listToAttrs (map (i: {
      name = "o${toString i}";
      value = mkOption { type = types.str; default = "def"; };
    }) (range 1 10));
  };
  mkAllSet = n: evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf t; default = {}; };
      config.u = builtins.listToAttrs (map (i: {
        name="u${toString i}";
        value = builtins.listToAttrs (map (j: { name="o${toString j}"; value="set"; }) (range 1 10));
      }) (range 1 n));
    }];
  };
  mkNoneSet = n: evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf t; default = {}; };
      config.u = builtins.listToAttrs (map (i: { name="u${toString i}"; value={}; }) (range 1 n));
    }];
  };
in {
  allset = builtins.deepSeq (mkAllSet 100).config.u "ok";
  noneset = builtins.deepSeq (mkNoneSet 100).config.u "ok";
}
