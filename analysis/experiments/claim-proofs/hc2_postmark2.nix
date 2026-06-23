let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules;
  submoduleType = types.submodule ({ name, specialArgs ? null, ... }: {
    options.x = mkOption { type = types.str; };
    options.seen = mkOption { type = types.str; default =
      if specialArgs != null then "SAW-SPECIALARGS:${toString (builtins.attrNames specialArgs)}"
      else "NO-SPECIALARGS-FROM-OUTER"; };
  });
  outer = evalModules {
    specialArgs = { postmark = "PRESENT"; };
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc.e0.x = "v"; }
    ];
  };
in outer.config.svc.e0.seen
