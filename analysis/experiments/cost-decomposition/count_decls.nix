let
  nixos = import <nixpkgs/nixos/lib/eval-config.nix> {
    system = "x86_64-linux";
    modules = [
      ({ lib, ... }: {
        boot.loader.grub.enable = false;
        fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
        system.stateVersion = "25.11";
        systemd.services.probe = { description = "p"; serviceConfig.ExecStart = "/bin/true"; };
      })
    ];
  };
  lib = import <nixpkgs/lib>;
  opts = nixos.options.systemd.services.type.getSubOptions [];
  countLeaves = o:
    if lib.isOption o then 1
    else if lib.isAttrs o then lib.foldl' (a: v: a + countLeaves v) 0 (lib.attrValues o)
    else 0;
in { topLevel = builtins.length (builtins.attrNames opts);
     totalLeaves = countLeaves opts; }
