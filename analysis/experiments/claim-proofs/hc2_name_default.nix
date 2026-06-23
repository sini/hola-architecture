let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  inherit (lib) types mkOption evalModules;
  mod = { name, ... }: {
    options.serverName = mkOption { type = types.str; default = name; };  # default depends on name
    options.port = mkOption { type = types.int; default = 80; };
  };
  result = evalModules {
    modules = [{
      options.vhosts = mkOption { type = types.attrsOf (types.submodule mod); default = {}; };
      config.vhosts."example.com" = {};
      config.vhosts."other.org" = { port = 8080; };
    }];
  };
in {
  a = result.config.vhosts."example.com";
  b = result.config.vhosts."other.org";
}
