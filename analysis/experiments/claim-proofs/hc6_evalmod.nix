# import <nixpkgs> {} attrNames + a bare lib.evalModules — claim: +99 copies
let
  pkgs = import (/home/sini/Documents/repos/nixpkgs) {};
  lib = pkgs.lib;
  ev = lib.evalModules { modules = [ { options.foo = lib.mkOption { type = lib.types.str; default = "x"; }; } ]; };
in
  builtins.length (builtins.attrNames pkgs) + (builtins.stringLength ev.config.foo)
