let
  eval = import /home/sini/Documents/repos/nixpkgs/nixos/lib/eval-config.nix {
    system = "x86_64-linux";
    modules = [ ({ ... }: { boot.isContainer = true; system.stateVersion = "24.05"; networking.hostName = "t"; }) ];
  };
in eval.config.networking.hostName
