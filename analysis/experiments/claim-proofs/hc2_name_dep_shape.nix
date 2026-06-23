let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules;
  # Submodule whose OPTION DECLARATIONS depend on `name` (the per-element arg).
  # This means the SHAPE itself is name-parametric — cannot be built once on base.
  mod = { name, ... }: {
    options = {
      ${"opt_" + name} = mkOption { type = types.int; default = 0; };  # dynamic option NAME
    };
    config.${"opt_" + name} = builtins.stringLength name;
  };
  result = evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf (types.submodule mod); default = {}; };
      config.u.alpha = {};
      config.u.bb = {};
    }];
  };
in {
  alpha = result.config.u.alpha;  # { opt_alpha = 5; }
  bb = result.config.u.bb;        # { opt_bb = 2; }
}
