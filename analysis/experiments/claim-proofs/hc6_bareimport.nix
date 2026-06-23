# Force only attrNames of import <nixpkgs> {} — no output values forced
let
  pkgs = import (/home/sini/Documents/repos/nixpkgs) {};
in
  builtins.length (builtins.attrNames pkgs)
