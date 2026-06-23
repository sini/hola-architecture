# just the fact of importing — force `builtins.seq` on the attrset keys count
let np = import <nixpkgs> { config = {}; overlays = []; }; in builtins.length (builtins.attrNames np)
