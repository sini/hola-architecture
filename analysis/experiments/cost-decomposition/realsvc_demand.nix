# Real eval-config systemd.services, but force ONLY .unit text vs nothing-extra.
# Compare: deepSeq full .text (claim's realsvc) vs force only the service NAME set (shape only).
{ n ? 1, force ? "text" }:
let
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [
      ({ lib, ... }: {
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
        system.stateVersion = "25.11";
        systemd.services = builtins.listToAttrs (lib.genList (i: {
          name = "svc${toString i}";
          value = { description = "service ${toString i}"; wantedBy = [ "multi-user.target" ]; serviceConfig.ExecStart = "/bin/true ${toString i}"; };
        }) n);
      })
    ];
  };
  lib = import <nixpkgs/lib>;
  svcs = lib.filterAttrs (k: v: lib.hasPrefix "svc" k) nixos.config.systemd.services;
in
  if force == "text"
  then builtins.deepSeq (builtins.mapAttrs (k: v: v.description) svcs) (builtins.length (builtins.attrNames svcs))
  else builtins.length (builtins.attrNames svcs)
