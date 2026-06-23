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
in
  if force == "text" then
    # full: render unit text (forces unit generator over each service submodule)
    let svcUnits = lib.filterAttrs (k: v: lib.hasSuffix ".service" k) nixos.config.systemd.units;
    in builtins.deepSeq (builtins.mapAttrs (k: v: v.text) svcUnits) (builtins.length (builtins.attrNames svcUnits))
  else if force == "set3" then
    # minimal: force ONLY the 3 set options per service (description, wantedBy, serviceConfig.ExecStart)
    builtins.deepSeq
      (builtins.mapAttrs (k: v: { d = v.description; w = v.wantedBy; e = v.serviceConfig.ExecStart or null; }) nixos.config.systemd.services)
      (builtins.length (builtins.attrNames nixos.config.systemd.services))
  else
    # names: force ONLY the attrnames of services (collection shape, no per-option value merge)
    builtins.length (builtins.attrNames nixos.config.systemd.services)
