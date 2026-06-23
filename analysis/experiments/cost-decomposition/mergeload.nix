{ n ? 50, layers ? 1 }:
let
  lib = import <nixpkgs/lib>;
  # `layers` separate modules each contributing definitions to the SAME services.
  # More layers => more per-option definitions => more value-merge work,
  # but identical declaration set (same submodule) => identical re-collection.
  mkLayer = l: ({ ... }: {
    boot.loader.grub.enable = false;
    fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
    system.stateVersion = "25.11";
    systemd.services = builtins.listToAttrs (lib.genList (i: {
      name = "svc${toString i}";
      value = {
        description = lib.mkDefault "svc ${toString i} layer ${toString l}";
        serviceConfig.ExecStart = lib.mkDefault "/bin/true ${toString i}.${toString l}";
        # each layer adds a distinct environment entry -> attrsOf merge across layers
        environment."V${toString l}" = "x${toString i}";
      };
    }) n);
  });
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = lib.genList mkLayer layers;
  };
  svcUnits = lib.filterAttrs (k: v: lib.hasSuffix ".service" k) nixos.config.systemd.units;
in
  builtins.deepSeq (builtins.mapAttrs (k: v: v.text) svcUnits) "ok"
