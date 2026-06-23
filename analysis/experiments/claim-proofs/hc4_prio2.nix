let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkForce mkBefore mkAfter;
  mkDef = f: v: { file = f; value = v; };
  legacy = t: defs: t.merge [ "test" ] defs;
  te = e: let r = builtins.tryEval e; in if r.success then r.value else "THREW";
in {
  listForce = te (legacy (types.listOf types.str) [ (mkDef "a" [ "low" ]) (mkDef "b" (mkForce [ "forced" ])) ]);
  listOrder = te (legacy (types.listOf types.str) [ (mkDef "a" (mkAfter [ "z" ])) (mkDef "b" (mkBefore [ "aa" ])) (mkDef "c" [ "m" ]) ]);
  typeErrThrows = (builtins.tryEval (lib.deepSeq (legacy (types.listOf types.int) [ (mkDef "a" [ "not-an-int" ]) ]) null)).success == false;
}
