let
  realLib = import ~/Documents/repos/nixpkgs/lib;
  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = args: (prev.modules.evalModules args) // { __TAG = "CUSTOM"; };
    };
  });
  sys = import ~/Documents/repos/nixpkgs/nixos/lib/eval-config.nix {
    lib = customLib;
    system = "x86_64-linux";
    modules = [
      ({ lib, ... }: {
        options.test.libIsCustom = lib.mkOption { type = lib.types.bool; default = false; };
        config = {
          test.libIsCustom = ((lib.evalModules { modules = []; }).__TAG or "PRISTINE") == "CUSTOM";
          boot.isContainer = true;
          system.stateVersion = "24.05";
          fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
        };
      })
    ];
  };
in { moduleLibIsCustom = sys.config.test.libIsCustom; }
