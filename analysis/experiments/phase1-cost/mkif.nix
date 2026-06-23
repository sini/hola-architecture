let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkOption mkIf types;
  ev = evalModules {
    modules = [
      { options.foo = mkOption { type = types.listOf types.str; default = ["base"]; }; }
      { config.foo = mkIf false [ "vanishes" ]; }  # discharged to [], default survives
    ];
  };
in ev.config.foo
