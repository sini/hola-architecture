let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  t = lib.types;
  mkDef = file: value: { inherit file value; };
  loc = [ "test" ];
  test = name: ty: defs:
    let
      viaLegacy = ty.merge loc defs;
      viaV2     = (ty.merge.v2 { inherit loc defs; }).value;
    in { inherit name; identical = viaLegacy == viaV2; legacy = viaLegacy; };
in
[
  (test "listOf" (t.listOf t.str) [ (mkDef "a" [ "x" "y" ]) (mkDef "b" [ "z" ]) ])
  (test "attrsOf" (t.attrsOf t.int) [ (mkDef "a" { p = 1; }) (mkDef "b" { q = 2; }) ])
  (test "either-listSide" (t.either (t.listOf t.str) t.int) [ (mkDef "a" [ "x" ]) (mkDef "b" [ "y" ]) ])
  (test "coercedTo" (t.coercedTo t.int (i: toString i) t.str) [ (mkDef "a" 42) ])
]
