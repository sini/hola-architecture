{ n ? 100, distinct ? true }:
let
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [ ({ lib, ... }: {
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
      system.stateVersion = "25.11";
      systemd.services = builtins.listToAttrs (lib.genList (i: {
        name = "svc${toString i}";
        value = { description = if distinct then "service ${toString i}" else "service";
                  wantedBy = [ "multi-user.target" ];
                  serviceConfig.ExecStart = if distinct then "/bin/true ${toString i}" else "/bin/true"; };
      }) n);
    }) ];
  };
  lib = import <nixpkgs/lib>;
  svcUnits = lib.filterAttrs (k: v: lib.hasSuffix ".service" k) nixos.config.systemd.units;
in builtins.deepSeq (builtins.mapAttrs (k: v: v.text) svcUnits) (builtins.length (builtins.attrNames svcUnits))
