let
  lib = import ~/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkIf mkOrder mkBefore mkAfter mkMerge;
  t = lib.types;
  E = mods: (evalModules { modules = mods; });
  try = e: builtins.tryEval (builtins.deepSeq e e);

  # a2: int, two diff values same prio -> throw (mergeDefaultOption int-equal rule)
  a2 = try (E [ { options.n = lib.mkOption { type=t.int; }; } { config.n=1; } { config.n=2; } ]).config.n;
  # a2b: int, SAME value twice -> ok
  a2b = try (E [ { options.n = lib.mkOption { type=t.int; }; } { config.n=5; } { config.n=5; } ]).config.n;
  # a3: force filters out the mkBefore (order) def entirely
  a3 = (E [ { options.l = lib.mkOption { type=t.listOf t.str; }; } { config.l = mkForce ["forced"]; } { config.l = mkBefore ["filtered"]; } ]).config.l;
  # a4: two forces, one wrapped in mkOrder 1500 -> both survive prio filter, order sorts
  a4 = (E [ { options.l = lib.mkOption { type=t.listOf t.str; }; } { config.l = mkOrder 1500 (mkForce ["z"]); } { config.l = mkForce ["a"]; } ]).config.l;
  # a5: anything with two lambdas -> merges function bodies recursively
  a5 = (E [ { options.f = lib.mkOption { type=t.anything; }; } { config.f = x: { p = x; }; } { config.f = x: { q = x; }; } ]).config.f 7;
  # a6: anything two ints, EQUAL required even at normal prio (not mergeDefaultOption!)
  a6 = try (E [ { options.v = lib.mkOption { type=t.anything; }; } { config.v = 1; } { config.v = 2; } ]).config.v;
  # a7: anything set merge -> recursive attrsOf anything, distinct keys union
  a7 = (E [ { options.v = lib.mkOption { type=t.anything; }; } { config.v = { a=1; }; } { config.v = { b=2; }; } ]).config.v;
in { a2=a2; a2b=a2b; a3=a3; a4=a4; a5=a5; a6=a6; a7=a7; }
