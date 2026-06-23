# Does extendModules re-collect the base per element, or share it?
# Test: put an expensive marker (builtins.trace-counted via a thunk that
# increments work) ... simpler: compare evalModules-count proxy.
# We measure: 1 element with B options vs N elements with B options.
# If base collect were SHARED, N elements would cost ~ base + N*delta.
# If re-collected, N elements cost ~ N*(base+delta). Already shown linear in N.
# Here: directly probe whether the submodule TYPE's `base` evalModules is
# evaluated once or N times by counting module-function applications.
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  # A submodule whose module-FUNCTION runs a traceable side marker.
  counter = builtins.trace "SUBMODULE-FN-APPLIED";
  submoduleType = types.submodule ({ name, ... }:
    builtins.seq (builtins.trace "BASE-FN-RUN" null) {
      options.x = mkOption { type = types.str; default = "d"; };
    });
  N = 5;
  elements = builtins.listToAttrs (genList (i: { name = "e${toString i}"; value = { x = "v${toString i}"; }; }) N);
  result = evalModules {
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = elements; }
    ];
  };
in builtins.deepSeq result.config.svc "OK"
