let
  pkgs = import <nixpkgs> {};
  lib0 = pkgs.lib;
  lib = lib0 // { evalModules = args: builtins.trace "EVALMODULES-FORCED" (lib0.evalModules args); };
  schemaLib = import "/nix/store/6p3b71s0sqvzh9jl9shc3cin23l0wbhq-source/nix/lib" {
    inputs.gen-algebra = (import "${builtins.getFlake "github:sini/gen-algebra"}/lib" { inherit lib; });
    inherit lib;
  };
  # RAW entry type — README:1018 says no mkOption wrapper, no introspection options.
  entryType = schemaLib.mkSchemaEntryType {};
  # Merge a single kind value directly via the type's merge function (bypass submodule/evalModules wrapper)
  merged = entryType.merge [ "service" ] [
    { file = "t"; value = { parent = "host"; options.owner = lib.mkOption { type = schemaLib.ref "host"; default = null; }; }; }
  ];
in {
  # Collection plane: parent extracted pre-merge — reachable WITHOUT evalModules?
  parent = merged.parent;
  kind = merged.kind;
}
