# A real NixOS eval. Read ONE trivial leaf: config.networking.hostName
let
  nixos = import (/home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix) {
    system = "x86_64-linux";
    modules = [ { networking.hostName = "h"; boot.loader.grub.enable = false; fileSystems."/" = { device = "x"; fsType = "ext4"; }; } ];
  };
in
  builtins.stringLength nixos.config.networking.hostName
