# Decompose per-element cost: a submodule with MANY option declarations but
# few values set (re-collection heavy) vs few declarations (merge-light).
# If re-collection dominates, a shared-base engine wins big; if the per-element
# extendModules collect is already cheap relative to merge, the prize is small.
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) evalModules mkOption types range;

  # HEAVY: 20 option declarations per submodule (realistic systemd.services has ~40)
  heavyType = types.submodule ({ name, ... }: {
    options = builtins.listToAttrs (map (i: {
      name = "opt${toString i}";
      value = mkOption { type = types.str; default = ""; };
    }) (range 1 20));
  });
  # LIGHT: 2 option declarations per submodule
  lightType = types.submodule ({ name, ... }: {
    options.a = mkOption { type = types.str; default = ""; };
    options.b = mkOption { type = types.str; default = ""; };
  });

  mk = t: n: evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf t; default = {}; };
      config.u = builtins.listToAttrs (map (i: { name="u${toString i}"; value={}; }) (range 1 n));
    }];
  };
in {
  heavy100 = builtins.deepSeq (mk heavyType 100).config.u "ok";
  light100 = builtins.deepSeq (mk lightType 100).config.u "ok";
}
