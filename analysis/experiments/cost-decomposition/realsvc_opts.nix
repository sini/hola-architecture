# Real systemd.services; force a CONTROLLED number of options per service (k of them).
# If per-svc cost scales with k (options demanded), the bulk is demand-driven per-option
# merge, NOT a fixed re-collection cost.
{ n ? 1, k ? 1 }:
let
  lib = import <nixpkgs/lib>;
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [
      ({ ... }: {
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
  svcs = lib.filterAttrs (key: v: lib.hasPrefix "svc" key) nixos.config.systemd.services;
  # pick first k option attrs of each service to force
  pickK = v: lib.listToAttrs (lib.take k (lib.mapAttrsToList (name: val: { inherit name; value = val; }) v));
in
  builtins.deepSeq (builtins.mapAttrs (key: v: pickK v) svcs) (builtins.length (builtins.attrNames svcs))
