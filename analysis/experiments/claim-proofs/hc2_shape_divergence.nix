let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules;

  result = evalModules {
    modules = [
      ({ lib, ... }: {
        options.units = mkOption {
          type = types.attrsOf (types.submodule {
            options.x = mkOption { type = types.int; default = 0; };
            # freeform type allows arbitrary extra attrs:
            freeformType = types.attrsOf types.anything;
          });
          default = {};
        };
        # element 'a' is a plain config def
        config.units.a = { x = 1; };
        # element 'b' IMPORTS a module that DECLARES A NEW OPTION 'y'
        config.units.b = { lib, ... }: {
          options.y = mkOption { type = types.int; default = 99; };
          config.x = 2;
          config.y = 7;
        };
      })
    ];
  };
in {
  a = result.config.units.a;
  b = result.config.units.b;
  # b has option y that a does NOT — the per-element SHAPE diverges
}
