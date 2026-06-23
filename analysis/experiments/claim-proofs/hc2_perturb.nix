# Can a per-element submodule definition ADD a new option declaration or
# imports, perturbing the shared base? If yes, base-sharing must detect it.
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules;
  submoduleType = types.submodule {
    options.x = mkOption { type = types.str; default = "base-default"; };
  };
  outer = evalModules {
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      # e0 is a plain value; e1 is a MODULE (function) that declares a NEW option
      { config.svc.e0.x = "plain"; }
      { config.svc.e1 = { config, ... }: {
          options.y = mkOption { type = types.int; default = 99; };
          config.x = "from-module";
        };
      }
    ];
  };
in { e0x = outer.config.svc.e0.x; e1x = outer.config.svc.e1.x; e1y = outer.config.svc.e1.y; }
