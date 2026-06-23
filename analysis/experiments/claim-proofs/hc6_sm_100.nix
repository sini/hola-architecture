let
  lib = (import (/home/sini/Documents/repos/nixpkgs) {}).lib;
  svc = lib.genAttrs (map (i: "svc${toString i}") (lib.range 1 100)) (n: { description = n; });
  nixos = import (/home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix) {
    system = "x86_64-linux";
    modules = [ { networking.hostName = "h"; boot.loader.grub.enable = false; fileSystems."/" = { device = "x"; fsType = "ext4"; }; systemd.services = svc; } ];
  };
in
  lib.foldl' (acc: n: acc + builtins.stringLength (nixos.config.systemd.services.${n}.description or "")) 0 (builtins.attrNames svc)
