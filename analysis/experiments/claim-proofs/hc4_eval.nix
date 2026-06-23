let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkForce mkBefore mkAfter mkOverride evalModules mkOption;
  eval = type: defs: (evalModules {
    modules = [ { options.x = mkOption { inherit type; }; } ] ++ map (d: { config.x = d; }) defs;
  }).config.x;
in {
  listForce  = eval (types.listOf types.str) [ [ "low" ] (mkForce [ "forced" ]) ];
  listOrder  = eval (types.listOf types.str) [ (mkAfter [ "z" ]) (mkBefore [ "aa" ]) [ "m" ] ];
  attrsOver  = eval (types.attrsOf types.int) [ { k = 1; } (mkOverride 50 { k = 99; }) ];
  typeErrThrows = (builtins.tryEval (lib.deepSeq (eval (types.listOf types.int) [ [ "bad" ] ]) null)).success == false;
}
