# Synthetic attrsOf (submodule) with a moderately-sized declaration set,
# to isolate per-element collect+merge cost. N elements, each with a single
# definition (fast-path leaf merge) so VALUE-MERGE is minimized -> residual
# is dominated by RE-COLLECTION + shape rebuild.
{ n ? 1, ndecls ? 20 }:
let
  lib = import <nixpkgs/lib>;
  inherit (lib) evalModules mkOption types genList foldl';
  # Build a submodule with `ndecls` declared options (string options).
  subOptions = builtins.listToAttrs (genList (i: {
    name = "opt${toString i}";
    value = mkOption { type = types.str; default = "d${toString i}"; };
  }) ndecls);
  subModule = { ... }: { options = subOptions; };
  eval = evalModules {
    modules = [
      {
        options.things = mkOption {
          type = types.attrsOf (types.submodule subModule);
          default = {};
        };
      }
      {
        # N elements, each defines exactly one option (single-def fast path)
        config.things = builtins.listToAttrs (genList (i: {
          name = "e${toString i}";
          value = { opt0 = "v${toString i}"; };
        }) n);
      }
    ];
  };
in
  # Force every element's config fully (deepSeq each element's whole attrset)
  builtins.deepSeq (lib.mapAttrs (k: v: v) eval.config.things) (builtins.attrNames eval.config.things)
