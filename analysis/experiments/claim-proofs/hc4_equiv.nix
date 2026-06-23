let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  t = lib.types;
  mkDef = file: value: { inherit file value; };
  # listOf str with two defs + an mkOrder + mkBefore to exercise merge algebra
  ty = t.listOf t.str;
  loc = [ "test" ];
  defs = [
    (mkDef "a.nix" [ "x" "y" ])
    (mkDef "b.nix" (lib.mkBefore [ "z" ]))
    (mkDef "c.nix" [ "w" ])
  ];
  viaLegacy = ty.merge loc defs;          # __functor path
  viaV2      = (ty.merge.v2 { inherit loc defs; }).value;
in {
  inherit viaLegacy viaV2;
  identical = viaLegacy == viaV2;
}
