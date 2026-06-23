{ n ? 100 }:
let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  sys = lib.nixosSystem or (import (pkgs.path + "/nixos/lib/eval-config.nix"));
  cfg = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [{
      boot.loader.grub.enable = false;
      fileSystems."/" = { device = "/dev/sda1"; fsType = "ext4"; };
      system.stateVersion = "24.05";
      systemd.services = lib.listToAttrs (lib.genList (i:
        lib.nameValuePair "svc${toString i}" {
          script = "echo ${toString i}";
          wantedBy = [ "multi-user.target" ];
        }) n);
    }];
  };
in builtins.seq (builtins.deepSeq (lib.mapAttrs (n: v: v.script or null) cfg.config.systemd.services) "ok") "done"
