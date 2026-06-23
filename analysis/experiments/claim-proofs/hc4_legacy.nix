let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types;
  mkDef = f: v: { file = f; value = v; };
  # For each v2 type, call the LEGACY interface `merge loc defs` directly
  # and compare against the v2 `.value`.
  legacy = t: defs: t.merge [ "test" ] defs;
  v2 = t: defs: (t.merge.v2 { loc = [ "test" ]; inherit defs; }).value;
  cmp = t: defs: let l = legacy t defs; r = v2 t defs; in { legacy = l; v2 = r; equal = l == r; };
in {
  listOf  = cmp (types.listOf types.str)  [ (mkDef "a" [ "x" ]) (mkDef "b" [ "y" "z" ]) ];
  attrsOf = cmp (types.attrsOf types.int) [ (mkDef "a" { p = 1; }) (mkDef "b" { q = 2; }) ];
  either  = cmp (types.either types.int types.str) [ (mkDef "a" 5) ];
  coerced = cmp (types.coercedTo types.int builtins.toString types.str) [ (mkDef "a" 42) ];
  # addCheck over a v2 type (nonEmptyListOf == addCheck (listOf ...) ...)
  nelist  = cmp (types.nonEmptyListOf types.str) [ (mkDef "a" [ "x" ]) ];
}
