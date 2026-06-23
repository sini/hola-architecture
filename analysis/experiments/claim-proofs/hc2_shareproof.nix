{ mode, N, B }:
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  baseModule = { options = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}"; value = mkOption { type = types.str; default = "d${toString i}"; };
  }) B); };
in
if mode == "submodule" then
  # Vanilla: N elements, each re-collects+re-merges the B-option base.
  let
    submoduleType = types.submodule baseModule;
    elements = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { opt0 = "v${toString i}"; }; }) N);
    r = evalModules { modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = elements; } ]; };
  in builtins.deepSeq r.config.svc "OK"
else if mode == "base-once" then
  # Lower bound: collect+merge the base ONE time (what a sharing engine pays for the SHAPE).
  let r = evalModules { modules = [ baseModule { config.opt0 = "v"; } ]; };
  in builtins.deepSeq r.config "OK"
else  # "n-flat": N independent flat evalModules of the base (no submodule wrapper)
  let
    rs = genList (i: evalModules { modules = [ baseModule { config.opt0 = "v${toString i}"; } ]; }) N;
  in builtins.deepSeq (map (r: r.config) rs) "OK"
