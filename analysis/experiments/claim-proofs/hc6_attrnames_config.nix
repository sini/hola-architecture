let
  nixos = import (/home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix) {
    system = "x86_64-linux";
    modules = [ { networking.hostName = "h"; boot.loader.grub.enable = false; fileSystems."/" = { device = "x"; fsType = "ext4"; }; } ];
  };
in
  builtins.length (builtins.attrNames nixos.config)
