# Soundness probe: does a submodule option default that references `name`
# (the per-element arg) get correctly per-element values, while the option
# DECLARATION shape (type, name) is element-independent? This is the seam a
# shared-base engine must respect: share the SHAPE, recompute name-dependent
# VALUE thunks per element.
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) evalModules mkOption types range;
  t = types.submodule ({ name, config, ... }: {
    options.description = mkOption { type = types.str; default = "svc-${name}"; };
    options.derived = mkOption { type = types.str; default = "d-${config.description}"; };
  });
  c = evalModules {
    modules = [{
      options.u = mkOption { type = types.attrsOf t; default = {}; };
      config.u = { alpha = {}; beta = { description = lib.mkForce "OVERRIDE"; }; };
    }];
  };
in {
  alphaDesc = c.config.u.alpha.description;     # default name-dependent => "svc-alpha"
  alphaDeriv = c.config.u.alpha.derived;        # derived from above => "d-svc-alpha"
  betaDesc = c.config.u.beta.description;        # mkForce => "OVERRIDE"
  betaDeriv = c.config.u.beta.derived;           # derived from forced => "d-OVERRIDE"
}
