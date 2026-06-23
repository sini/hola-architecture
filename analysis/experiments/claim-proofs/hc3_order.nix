let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkBefore mkAfter mkForce;
  ev = mods: (evalModules { modules = mods; }).config;
  # Same two lines, swapped module order -> different result? (non-commutativity)
  fwd = (ev [ { options.x = lib.mkOption { type = lib.types.lines; }; } { config.x = "A"; } { config.x = "B"; } ]).x;
  rev = (ev [ { options.x = lib.mkOption { type = lib.types.lines; }; } { config.x = "B"; } { config.x = "A"; } ]).x;
  # mkBefore A then plain B -> A before B regardless? (priority reorders the positional default)
  ord = (ev [ { options.x = lib.mkOption { type = lib.types.lines; }; } { config.x = "B"; } { config.x = mkBefore "A"; } ]).x;
  # lists in attrsOf submodule: per-element fresh evalModules; the H7 kernel
in { inherit fwd rev ord; }
