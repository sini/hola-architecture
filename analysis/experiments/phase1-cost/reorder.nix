let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkOption mkForce mkDefault types;
  ev = evalModules {
    modules = [
      { options.foo = mkOption { type = types.listOf types.str; default = []; }; }
      { config.foo = mkForce [ "c" ]; }     # FIRST positionally, prio 50
      { config.foo = mkDefault [ "z" ]; }   # LAST positionally, prio 1000
      { config.foo = [ "n" ]; }             # normal, prio 1000
    ];
  };
in ev.config.foo
