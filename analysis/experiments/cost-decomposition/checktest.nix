{ n ? 50, check ? true }:
let
  lib = import <nixpkgs/lib>;
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [
      ({ ... }: {
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
        system.stateVersion = "25.11";
        _module.check = check;
        systemd.services = builtins.listToAttrs (lib.genList (i: {
          name = "svc${toString i}";
          value = { description = "s${toString i}"; serviceConfig.ExecStart = "/bin/true ${toString i}"; };
        }) n);
      })
    ];
  };
  svcUnits = lib.filterAttrs (k: v: lib.hasSuffix ".service" k) nixos.config.systemd.units;
in builtins.deepSeq (builtins.mapAttrs (k: v: v.text) svcUnits) "ok"
