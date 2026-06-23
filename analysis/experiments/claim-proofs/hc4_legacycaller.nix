let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types;
  # Simulate the PRE-v2 caller logic (nixpkgs mergeDefinitions before Aug 2025):
  #   if all (def: type.check def.value) defsFinal then type.merge loc defsFinal else throw
  # type.check may now be an attrset-functor; calling it as a function still works via __functor.
  legacyCaller = type: loc: defsFinal:
    if builtins.all (def: type.check def.value) defsFinal
    then type.merge loc defsFinal
    else throw "type error";
  mkDef = f: v: { file = f; value = v; };
in {
  # check-as-attrset still callable as function?
  checkCallable = (types.listOf types.str).check [ "x" ];
  # full legacy-caller path on v2 types with already-discharged (plain) defs:
  listOf  = legacyCaller (types.listOf types.str)  ["l"] [ (mkDef "a" [ "x" ]) (mkDef "b" [ "y" ]) ];
  attrsOf = legacyCaller (types.attrsOf types.int) ["l"] [ (mkDef "a" { p = 1; }) (mkDef "b" { q = 2; }) ];
  either  = legacyCaller (types.either types.int types.str) ["l"] [ (mkDef "a" "hi") ];
  coerced = legacyCaller (types.coercedTo types.int builtins.toString types.str) ["l"] [ (mkDef "a" 7) ];
  submod  = (legacyCaller (types.submoduleWith { modules = [ { options.y = lib.mkOption { type = types.int; default = 3; }; } ]; }) ["l"] [ (mkDef "a" {}) ]).y;
}
