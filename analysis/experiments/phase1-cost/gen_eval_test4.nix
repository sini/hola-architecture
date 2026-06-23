let
  pkgs = import <nixpkgs> {};
  lib0 = pkgs.lib;
  lib = lib0 // { evalModules = args: builtins.trace "EVALMODULES-FORCED" (lib0.evalModules args); };
  schemaLib = import "/nix/store/6p3b71s0sqvzh9jl9shc3cin23l0wbhq-source/nix/lib" {
    inputs.gen-algebra = (import "${builtins.getFlake "github:sini/gen-algebra"}/lib" { inherit lib; });
    inherit lib;
  };
  entryType = schemaLib.mkSchemaEntryType {};
  merged = entryType.merge [ "service" ] [
    { file = "t"; value = { parent = "host"; options.owner = lib.mkOption { type = schemaLib.ref "host"; default = null; }; }; }
  ];
in { refs = merged.refs; }
