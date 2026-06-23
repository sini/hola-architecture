let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules;

  # Instrument: count how many option leaves in a submodule element are single-def vs multi-def.
  # We approximate by checking _module.args.name (the suspect) merges fine.
  result = evalModules {
    modules = [{
      options.units = mkOption {
        type = types.attrsOf (types.submodule ({ name, ... }: {
          options.x = mkOption { type = types.int; default = 0; };
          options.nm = mkOption { type = types.str; default = name; };
        }));
        default = {};
      };
      config.units.foo.x = 1;
    }];
  };
in {
  nm = result.config.units.foo.nm;  # should be "foo" — name resolved through default+override merge
  x = result.config.units.foo.x;
}
