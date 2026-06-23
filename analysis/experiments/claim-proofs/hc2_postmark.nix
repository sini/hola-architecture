# Can a WRAPPER around evalModules survive into submodule extendModules?
# A wrapper would intercept the top-level eval. But submodule recursion calls
# the INTERNAL captured `evalModules` (modules.nix:386), not our wrapper.
# Test: stamp specialArgs at the top; check if a custom arg injected by a
# wrapper-at-top-level reaches the per-element extendModules base re-eval.
let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;
  submoduleType = types.submodule ({ name, postmark ? "ABSENT", ... }: {
    options.x = mkOption { type = types.str; default = "d"; };
    config.x = builtins.trace "POSTMARK=${postmark}" "v";
  });
  # Simulate a "wrapper" that injects postmark only at the OUTER evalModules.
  outer = evalModules {
    specialArgs = { postmark = "PRESENT"; };  # outer specialArgs
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = { e0 = {}; }; }
    ];
  };
in builtins.deepSeq outer.config.svc "OK"
