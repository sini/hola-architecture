let
  lib = import ~/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkIf mkOrder mkBefore mkAfter mkMerge;
  t = lib.types;

  # ATTACK 1: types.anything — merge dispatches on RUNTIME VALUE TYPE, not declared type.
  # Two normal defs, same priority. anything.merge recurses; ints must be equal, lists concat,
  # attrs deep-merge, bools OR, strings concat. This is value-shape-directed, NOT positional.
  a1 = (evalModules {
    modules = [
      { options.v = lib.mkOption { type = t.anything; }; }
      { config.v = { a = [ 1 ]; b = true; }; }
      { config.v = { a = [ 2 ]; c = "x"; }; }
    ];
  }).config.v;

  # ATTACK 2: mergeDefaultOption int rule — all ints must be EQUAL or throw, even at same prio.
  a2 = builtins.tryEval (evalModules {
    modules = [
      { options.n = lib.mkOption { type = t.int; }; }
      { config.n = 1; }
      { config.n = 2; }
    ];
  }).config.n;

  # ATTACK 3: priority interacts with order. mkForce on one, mkBefore (order) on another.
  # filterOverrides runs BEFORE sortProperties. So force (prio 50) filters out the order'd
  # normal-prio def entirely. Order only sorts among survivors of priority filter.
  a3 = (evalModules {
    modules = [
      { options.l = lib.mkOption { type = t.listOf t.str; }; }
      { config.l = mkForce [ "forced" ]; }
      { config.l = mkBefore [ "before-but-filtered" ]; }
    ];
  }).config.l;

  # ATTACK 4: mkOrder on a mkForce'd value — order priority survives filterOverrides
  # because override-prio and order-prio are ORTHOGONAL axes carried on the same def.
  a4 = (evalModules {
    modules = [
      { options.l = lib.mkOption { type = t.listOf t.str; }; }
      { config.l = mkOrder 1500 (mkForce [ "z" ]); }
      { config.l = mkForce [ "a" ]; }
    ];
  }).config.l;
in { inherit a1 a2 a3 a4; }
