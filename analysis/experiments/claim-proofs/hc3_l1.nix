let
  lib = import ~/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkIf mkOrder mkBefore mkAfter mkMerge;
  # L1: priority fold non-positional. normal, mkForce, mkDefault, mkIf false, mkOrder 10
  eval1 = evalModules {
    modules = [
      { options.x = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
      { config.x = [ "n" ]; }                 # normal (prio 100)
      { config.x = mkForce [ "c" ]; }         # prio 50
      { config.x = mkDefault [ "z" ]; }       # prio 1000
      { config.x = mkIf false [ "gone" ]; }   # evaporates
      { config.x = mkOrder 10 [ "ord" ]; }    # order, prio 100
    ];
  };
  # L2: order non-positional. mkAfter, normal, mkBefore
  eval2 = evalModules {
    modules = [
      { options.y = lib.mkOption { type = lib.types.listOf lib.types.str; }; }
      { config.y = mkAfter [ "last" ]; }
      { config.y = [ "mid" ]; }
      { config.y = mkBefore [ "first" ]; }
    ];
  };
in { l1 = eval1.config.x; l2 = eval2.config.y; }
