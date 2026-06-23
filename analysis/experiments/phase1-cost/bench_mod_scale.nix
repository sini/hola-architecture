let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  mkMod = n: { config.env = builtins.listToAttrs (map (i: { name = "k${toString n}_${toString i}"; value = i; }) (lib.range 1 50)); };
  res = lib.evalModules {
    modules = [ { options.env = lib.mkOption { type = lib.types.attrsOf lib.types.int; default = {}; }; } ]
      ++ map mkMod (lib.range 1 200);
  };
in builtins.length (builtins.attrNames res.config.env)
