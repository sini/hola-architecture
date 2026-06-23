let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkForce mkOverride mkOrder mkBefore mkAfter;
  mkDef = f: v: { file = f; value = v; };
  legacy = t: defs: t.merge [ "test" ] defs;
in {
  # mkForce through listOf via legacy merge entry
  listForce = legacy (types.listOf types.str) [
    (mkDef "a" [ "low" ])
    (mkDef "b" (mkForce [ "forced" ]))
  ];
  # ordering through listOf
  listOrder = legacy (types.listOf types.str) [
    (mkDef "a" (mkAfter [ "z" ]))
    (mkDef "b" (mkBefore [ "a" ]))
    (mkDef "c" [ "m" ])
  ];
  # mkOverride priority through attrsOf
  attrsOverride = legacy (types.attrsOf types.int) [
    (mkDef "a" { k = 1; })
    (mkDef "b" (mkOverride 50 { k = 99; }))
  ];
  # type error path: legacy merge on bad value -> should THROW (not silently pass)
  typeErr = builtins.tryEval (legacy (types.listOf types.int) [ (mkDef "a" [ "not-an-int" ]) ]);
}
