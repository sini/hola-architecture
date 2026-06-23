let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkMerge mkIf mkDefault;
  ev = mods: (evalModules { modules = mods; });
  # H1: coercedTo - merge has to run the coercion AND merge; order of coercion vs merge
  coerced = (ev [
    { options.c = lib.mkOption { type = lib.types.coercedTo lib.types.int (i: toString i) lib.types.str; }; }
    { config.c = 42; }       # int, coerced
    { config.c = mkForce "x"; } # str force
  ]).config.c;
  # H2: nested submodule - per-element fresh evalModules, mkDefault inside
  sub = (ev [
    { options.s = lib.mkOption { type = lib.types.submodule { options.a = lib.mkOption { type = lib.types.int; default = 7; }; }; }; }
    { config.s.a = mkDefault 5; }
    { config.s = mkForce { a = 9; }; }   # force the WHOLE submodule
  ]).config.s;
  # H3: attrsOf submodule - mkForce on one key, mkIf on whole attrset
  units = (ev [
    { options.u = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { options.x = lib.mkOption { type = lib.types.int; }; }); }; }
    { config.u.foo.x = 1; }
    { config.u = mkIf true { bar.x = 2; }; }
    { config.u.foo.x = mkForce 99; }
  ]).config.u;
in { inherit coerced sub units; }
