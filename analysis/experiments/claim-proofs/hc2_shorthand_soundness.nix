let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules;
  # types.submodule: shorthandOnlyDefinesConfig=true. Attrset element CANNOT add options.
  result = evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf (types.submodule {
        options.x = mkOption { type = types.int; default = 0; };
      }); default = {}; };
      # try to sneak an option in via attrset element — should FAIL (unmatched def) or be ignored
      config.u.a = { x = 1; y = 99; };
    }];
  };
in result.config.u.a
