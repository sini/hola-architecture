let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) types mkOption evalModules genList;

  N = 250;
  B = 20;

  mkBaseOpts = prefix:
    builtins.listToAttrs (genList (i: {
      name = "${prefix}${toString i}";
      value = mkOption { type = types.str; default = "d${toString i}"; };
    }) B);

  submoduleType = types.submodule ({ name, ... }: {
    options = mkBaseOpts "opt";
  });

  elements = builtins.listToAttrs (genList (i: {
    name = "e${toString i}";
    value = {
      opt0 = "v${toString i}a";
      opt1 = "v${toString i}b";
      opt2 = "v${toString i}c";
    };
  }) N);

  result = evalModules {
    modules = [
      { options.svc = mkOption { type = types.attrsOf submoduleType; default = {}; }; }
      { config.svc = elements; }
    ];
  };
in
  builtins.deepSeq result.config.svc "OK"
