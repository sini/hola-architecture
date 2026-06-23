# Test HC5's "override submoduleWith/attrsOf is a NO-OP (local bindings)".
# submoduleWith does `inherit (lib.modules) evalModules;` and types.nix functions
# reference each other via the types.nix-local `let rec`. Does overriding
# lib.types.submoduleWith change which submoduleWith attrsOf uses internally?
let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;
  mkCustomLib = realLib.extend (final: prev: {
    types = prev.types // {
      submoduleWith = args:
        builtins.trace "OVERRIDE types.submoduleWith CALLED"
        (prev.types.submoduleWith args);
    };
  });
  testModule = { lib, ... }: {
    options.svc = lib.mkOption {
      # attrsOf submodule => internally types.submodule => submoduleWith
      type = lib.types.attrsOf (lib.types.submodule {
        options.x = lib.mkOption { type = lib.types.int; default = 1; };
      });
      default = {};
    };
    config.svc.a.x = 5;
  };
  customEval = mkCustomLib.evalModules { modules = [ testModule ]; };
in builtins.deepSeq customEval.config.svc.a.x "DONE"
