{ n ? 250, check ? true }:
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules genList;
  serviceModule = { name, ... }: {
    options = lib.genAttrs (map (i: "opt${toString i}") (lib.range 1 30))
      (o: mkOption { type = types.nullOr types.str; default = null; });
    config._module.check = check;
    config.opt1 = "svc-${name}";
  };
  result = evalModules {
    modules = [{
      options.services = mkOption { type = types.attrsOf (types.submodule serviceModule); default = {}; };
      config.services = lib.listToAttrs (genList (i: lib.nameValuePair "s${toString i}" { opt2 = "v${toString i}"; }) n);
    }];
  };
in builtins.deepSeq result.config.services result.config.services."s0".opt1
