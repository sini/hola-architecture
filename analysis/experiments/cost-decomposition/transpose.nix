{ mode ? "one" }:
let
  lib = import <nixpkgs/lib>;
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [
      ({ ... }: {
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
        system.stateVersion = "25.11";
      })
    ];
  };
in
  if mode == "one" then
    # read a single trivial leaf option -> forces the top-level transpose
    # (declsByName for the whole NixOS namespace must be built to locate it)
    nixos.config.system.stateVersion
  else if mode == "names" then
    # force only attrNames of config (the shape spine), not values
    builtins.length (builtins.attrNames nixos.config)
  else
    nixos.config.system.stateVersion
