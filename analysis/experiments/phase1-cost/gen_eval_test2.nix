let
  pkgs = import <nixpkgs> {};
  lib0 = pkgs.lib;
  # Poison evalModules to detect whether the ref-edge plane forces it.
  lib = lib0 // {
    evalModules = args: builtins.trace "EVALMODULES-FORCED" (lib0.evalModules args);
  };
  schemaLib = import "/nix/store/6p3b71s0sqvzh9jl9shc3cin23l0wbhq-source/nix/lib" {
    inputs.gen-algebra = (import "${builtins.getFlake "github:sini/gen-algebra"}/lib" { inherit lib; });
    inherit lib;
  };
  evaluated = lib0.evalModules {
    modules = [{
      options.schema = schemaLib.mkSchemaOption {};
      config.schema = {
        host = { options.name = lib.mkOption { type = lib.types.str; default = "h"; }; };
        service = { parent = "host"; options.owner = lib.mkOption { type = schemaLib.ref "host"; default = null; }; };
      };
    }];
  };
  s = evaluated.config.schema;
in {
  # PARENT edges only — should NOT need per-kind evalModules
  parentOnly = builtins.filter (e: e.type == "parent") s._edges;
  # REF edges — derived from .refs which forces introspect/evalModules
  refOnly = builtins.filter (e: e.type == "ref") s._edges;
}
