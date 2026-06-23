let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types;
  te = e: (builtins.tryEval e);
  probe = t: {
    name = t.name or "?";
    hasV2 = t.merge ? v2;
    checkIsAttrs = builtins.isAttrs t.check;
    checkV2Coherent = let r = te (t.check.isV2MergeCoherent or "absent"); in if r.success then r.value else "ERR";
    mergeKeys = if builtins.isAttrs t.merge then builtins.attrNames t.merge else "function";
  };
in {
  str          = probe types.str;
  int          = probe types.int;
  bool         = probe types.bool;
  path         = probe types.path;
  attrs        = probe types.attrs;
  raw          = probe types.raw;
  anything     = probe types.anything;
  listOf_str   = probe (types.listOf types.str);
  attrsOf_str  = probe (types.attrsOf types.str);
  either       = probe (types.either types.int types.str);
  coercedTo    = probe (types.coercedTo types.int builtins.toString types.str);
  addCheck     = probe (types.addCheck types.int (x: x > 0));
  nullOr       = probe (types.nullOr types.str);
  enum         = probe (types.enum [ "a" "b" ]);
  oneOf        = probe (types.oneOf [ types.int types.str ]);
  submoduleWith = probe (types.submoduleWith { modules = []; });
  uniq         = probe (types.uniq types.str);
  lines        = probe types.lines;
  separatedString = probe (types.separatedString ",");
  functionTo   = probe (types.functionTo types.str);
  attrTag      = probe (types.attrTag { foo = lib.mkOption { type = types.int; }; });
}
