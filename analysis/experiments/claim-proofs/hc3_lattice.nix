let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault mkMerge mkOrder;
  ev = mods: (evalModules { modules = mods; }).config;
  # T1: string merge is ORDER-SENSITIVE concat (non-commutative join) via mergeDefaultOption? No - strOption uses mergeEqualOption. Use separatedString/lines.
  # Use types.lines (concat with newline, order-sensitive)
  linesAB = (ev [
    { options.x = lib.mkOption { type = lib.types.lines; }; }
    { config.x = "A"; }
    { config.x = "B"; }
  ]).x;
  # T2: int with two unequal defs -> mergeEqualOption THROWS (not a total join)
  intConflict = builtins.tryEval (ev [
    { options.y = lib.mkOption { type = lib.types.int; }; }
    { config.y = 1; }
    { config.y = 2; }
  ]).y;
  # T3: attrsOf merge with same key from two modules: recursion/merge, order in valueMeta?
  # T4: commutativity of priority: mkForce regardless of position already shown.
  # T5: TWO mkForce equal priority unequal value on int -> throws (force does not pick a winner; conflict at same prio)
  twoForce = builtins.tryEval (ev [
    { options.z = lib.mkOption { type = lib.types.int; }; }
    { config.z = mkForce 1; }
    { config.z = mkForce 2; }
  ]).z;
in {
  linesAB = linesAB;
  intConflict = { ok = intConflict.success; };
  twoForce = { ok = twoForce.success; };
}
