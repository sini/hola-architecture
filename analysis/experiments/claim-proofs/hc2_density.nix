{ n ? 250 }:
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules genList;

  # A submodule with a realistic-ish option count (systemd.services-like: ~30 options)
  serviceModule = { name, ... }: {
    options = lib.genAttrs (map (i: "opt${toString i}") (lib.range 1 30))
      (o: mkOption { type = types.nullOr types.str; default = null; });
    config.opt1 = "svc-${name}";
  };

  result = evalModules {
    modules = [{
      options.services = mkOption {
        type = types.attrsOf (types.submodule serviceModule);
        default = {};
      };
      config.services = lib.listToAttrs (genList (i:
        lib.nameValuePair "s${toString i}" { opt2 = "v${toString i}"; }
      ) n);
    }];
  };
in
  # Force the full product (like system.build.toplevel forces all units)
  builtins.deepSeq result.config.services result.config.services."s0".opt1
