{ n ? 1, force ? "one" }:
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
  lib = import <nixpkgs/lib>;
  svcs = nixos.config.systemd.services;
in
  if force == "one" then
    # Force exactly ONE leaf per element: description. This DEMANDS each element's
    # submodule config (=> per-element evalModules collection runs) but merges only 1 leaf.
    builtins.deepSeq (builtins.mapAttrs (k: v: v.description) svcs) (builtins.length (builtins.attrNames svcs))
  else if force == "enable" then
    # Force a single declared-but-unset boolean leaf (its default) per element.
    builtins.deepSeq (builtins.mapAttrs (k: v: v.enable) svcs) (builtins.length (builtins.attrNames svcs))
  else
    builtins.length (builtins.attrNames svcs)
