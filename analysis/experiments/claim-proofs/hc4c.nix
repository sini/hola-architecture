let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  t = lib.types;
  probe = name: ty: {
    inherit name;
    hasV2 = ty.merge ? v2;
    mergeIsRawLambda = builtins.isFunction ty.merge;
    checkIsAttrs = builtins.isAttrs ty.check;
    checkCoherent = (ty.check.isV2MergeCoherent or "absent");
  };
in
builtins.listToAttrs (map (p: { name = p.name; value = removeAttrs p ["name"]; }) [
  (probe "listOf"        (t.listOf t.str))
  (probe "attrsOf"       (t.attrsOf t.str))
  (probe "either"        (t.either t.str t.int))
  (probe "coercedTo"     (t.coercedTo t.int (i: toString i) t.str))
  (probe "addCheck"      (t.addCheck t.str (s: s != "")))
  (probe "submoduleWith" (t.submoduleWith { modules = []; }))
  (probe "nullOr"        (t.nullOr t.str))
  (probe "bool"          t.bool)
  (probe "int"           t.int)
  (probe "str"           t.str)
  (probe "attrs"         t.attrs)
  (probe "enum"          (t.enum [ "a" "b" ]))
  (probe "package"       t.package)
  (probe "functionTo"    (t.functionTo t.str))
  (probe "nullOr_of_listOf" (t.nullOr (t.listOf t.str)))
])
