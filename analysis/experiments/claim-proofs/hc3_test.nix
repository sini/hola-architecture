let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkIf mkOrder mkBefore mkAfter mkOverride types mkOption;
  r1 = (evalModules {
    modules = [
      { options.x = mkOption { type = types.str; }; }
      { config.x = "n"; }
      { config.x = mkForce "c"; }
      { config.x = mkDefault "z"; }
      { config.x = mkIf false "evaporates"; }
      { config.x = mkOrder 10 "ordered-but-loses-on-prio"; }
    ];
  }).config.x;
  r2 = (evalModules {
    modules = [
      { options.l = mkOption { type = types.listOf types.str; }; }
      { config.l = mkAfter [ "last" ]; }
      { config.l = [ "mid" ]; }
      { config.l = mkBefore [ "first" ]; }
    ];
  }).config.l;
in { inherit r1 r2; }
