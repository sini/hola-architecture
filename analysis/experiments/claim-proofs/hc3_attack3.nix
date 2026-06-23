let
  lib = import ~/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkIf mkOrder mkBefore mkAfter mkMerge mkOverride;
  t = lib.types;
  E = mods: (evalModules { modules = mods; });
  try = e: builtins.tryEval (builtins.deepSeq e e);

  # a4 re-probe: two mkForce, one ALSO mkOrder1500. why ["a"] only? because both forced -> survive,
  # but each def is still a SINGLE list; result should be sorted-concat of [z] and [a].
  a4 = (E [ { options.l = lib.mkOption { type=t.listOf t.str; }; }
            { config.l = mkOrder 1500 (mkForce ["z"]); }
            { config.l = mkForce ["a"]; } ]).config.l;
  # a4b: same but NO inner force on the ordered one -> ordered one is prio100, gets filtered by the force(50)
  a4b = (E [ { options.l = lib.mkOption { type=t.listOf t.str; }; }
            { config.l = mkOrder 1500 ["z"]; }
            { config.l = mkForce ["a"]; } ]).config.l;
  # a4c: both normal prio, one ordered after -> concat in sort order
  a4c = (E [ { options.l = lib.mkOption { type=t.listOf t.str; }; }
            { config.l = mkAfter ["z"]; }
            { config.l = ["a"]; } ]).config.l;

  # SUBMODULE priority: mkForce at the WHOLE-submodule level vs per-attr.
  sub = t.submodule { options = { p = lib.mkOption { type=t.int; default=0; }; q = lib.mkOption { type=t.str; default="d"; }; }; };
  s1 = (E [ { options.s = lib.mkOption { type=sub; }; }
            { config.s = { p = 1; q = "keep"; }; }
            { config.s = mkForce { p = 2; }; } ]).config.s;  # does force on whole submodule wipe q?

  # apply function runs AFTER merge
  ap = (E [ { options.a = lib.mkOption { type=t.listOf t.int; apply = xs: builtins.length xs; }; }
            { config.a = [1]; } { config.a = [2 3]; } ]).config.a;

  # freeform: _module.freeformType captures unmatched defs, merged via freeform type
  ff = (E [ { config._module.freeformType = t.attrsOf t.int; options.known = lib.mkOption { type=t.int; default=0;}; }
            { config.unknown1 = 7; config.unknown2 = 9; config.known = 3; } ]).config;
in { a4=a4; a4b=a4b; a4c=a4c; s1=s1; ap=ap; ff=ff; }
