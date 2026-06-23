# Module system eval over a trivial config (no nixpkgs package set forced)
let
  np = import <nixpkgs> {};
  res = np.lib.evalModules { modules = [ { options = {}; config = {}; } ]; };
in builtins.attrNames res.config
