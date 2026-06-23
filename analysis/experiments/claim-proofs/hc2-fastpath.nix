# Measure: for an attrsOf submodule with N elements, how many option reads
# hit the fast path vs miss it due to mkOptionDefault prepend.
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) evalModules mkOption types;

  # A submodule with options that mostly have defaults (the common case).
  unitType = types.submodule ({ name, ... }: {
    options = {
      enable = mkOption { type = types.bool; default = true; };       # has default
      description = mkOption { type = types.str; default = name; };    # has default
      script = mkOption { type = types.str; default = ""; };           # has default
      wantedBy = mkOption { type = types.listOf types.str; default = []; }; # has default
      command = mkOption { type = types.str; };                        # NO default
    };
  });

  mkConfig = n: evalModules {
    modules = [{
      options.units = mkOption { type = types.attrsOf unitType; default = {}; };
      config.units = builtins.listToAttrs (map (i: {
        name = "unit${toString i}";
        value = { command = "run-${toString i}"; };  # only set the no-default opt
      }) (lib.range 1 n));
    }];
  };
in {
  c10  = builtins.deepSeq (mkConfig 10).config.units  "ok10";
  c100 = builtins.deepSeq (mkConfig 100).config.units "ok100";
  c250 = builtins.deepSeq (mkConfig 250).config.units "ok250";
}
