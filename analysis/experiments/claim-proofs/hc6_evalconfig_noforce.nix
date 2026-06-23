let
  nixos = import (/home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix) {
    system = "x86_64-linux";
    modules = [ { networking.hostName = "h"; boot.loader.grub.enable = false; fileSystems."/" = { device = "x"; fsType = "ext4"; }; } ];
  };
in
  # force NOTHING about config/options — just that the eval-config call returns an attrset
  builtins.isAttrs nixos
