{ mode ? "bareeval" }:
let lib = import <nixpkgs/lib>;
in
  if mode == "bareeval" then
    # minimal evalModules: 1 option, 1 def. The irreducible machinery floor.
    (lib.evalModules { modules = [ { options.x = lib.mkOption { type = lib.types.str; default = "a"; }; } ]; }).config.x
  else if mode == "modlist" then
    # collect the whole NixOS module list but read nothing
    let n = import <nixpkgs/nixos/lib/eval-config.nix> {
      system = "x86_64-linux";
      modules = [ ({...}:{ boot.loader.grub.enable=false; fileSystems."/"={device="/dev/sda1";fsType="ext4";}; system.stateVersion="25.11"; }) ];
    }; in builtins.seq n._module.args.pkgs.system "imported"
  else "x"
