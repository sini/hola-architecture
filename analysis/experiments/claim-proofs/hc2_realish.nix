{ n ? 250 }:
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  systemdTypes = import (pkgs.path + "/nixos/lib/systemd-lib.nix") { inherit lib config pkgs utils; };
  config = {};
  utils = {};
in
  # measure cost of building N systemd-service-like submodule elements through the REAL systemd-types
  builtins.length (builtins.attrNames (import (pkgs.path + "/nixos/lib/systemd-types.nix") { inherit lib systemdUtils pkgs; }))
