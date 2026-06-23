{ n ? 1 }:
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
          value = {
            description = "service ${toString i}";
            wantedBy = [ "multi-user.target" ];
            serviceConfig.ExecStart = "/bin/true ${toString i}";
          };
        }) n);
      })
    ];
  };
  lib = nixos.config.nixpkgs.lib or (import <nixpkgs/lib>);
  # Force each generated service unit's rendered text. systemd.units."svcK.service".text
  svcUnits = lib.filterAttrs (k: v: lib.hasSuffix ".service" k) nixos.config.systemd.units;
in
  builtins.deepSeq
    (builtins.mapAttrs (k: v: v.text) svcUnits)
    (builtins.length (builtins.attrNames svcUnits))
