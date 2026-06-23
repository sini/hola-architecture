let
  lib = (import (/home/sini/Documents/repos/nixpkgs) {}).lib;
  svc = lib.genAttrs (map (i: "svc${toString i}") (lib.range 1 50)) (n: { script = "echo ${n}"; });
  nixos = import (/home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix) {
    system = "x86_64-linux";
    modules = [ { networking.hostName = "h"; boot.loader.grub.enable = false; fileSystems."/" = { device = "x"; fsType = "ext4"; }; systemd.services = svc; } ];
  };
in
  # Force the systemd.services attr set spine + each unit's Unit section name -> drives submodule evalModules per element
  builtins.length (builtins.attrNames nixos.config.systemd.services) +
  lib.foldl' (acc: n: acc + builtins.stringLength (nixos.config.systemd.services.${n}.serviceConfig.ExecStart or "")) 0 (builtins.attrNames svc)
