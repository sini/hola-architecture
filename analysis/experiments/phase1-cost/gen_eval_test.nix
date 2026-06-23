let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  schemaLib = import "/nix/store/6p3b71s0sqvzh9jl9shc3cin23l0wbhq-source/nix/lib" {
    inputs.gen-algebra = (import "${builtins.getFlake "github:sini/gen-algebra"}/lib" { inherit lib; });
    inherit lib;
  };
  # Define a schema with a ref edge to inspect the graph plane
  evaluated = lib.evalModules {
    modules = [
      {
        options.schema = schemaLib.mkSchemaOption {};
        config.schema = {
          host = { options.name = lib.mkOption { type = lib.types.str; default = "h"; }; };
          service = {
            parent = "host";
            options.owner = lib.mkOption { type = schemaLib.ref "host"; default = null; };
          };
        };
      }
    ];
  };
  s = evaluated.config.schema;
in {
  # Does reading _edges (graph plane) require evalModules of each kind?
  edges = s._edges;
  topology = s._topology;
  roots = s._roots;
}
