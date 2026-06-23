let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;
  mkCustomLib = realLib.extend (final: prev: {
    types = prev.types // {
      submoduleWith = args: builtins.trace "OVERRIDE-DIRECT" (prev.types.submoduleWith args);
    };
  });
  t = mkCustomLib.types.submoduleWith { modules = [ { options = {}; } ]; };
in builtins.deepSeq t.name "DONE"
