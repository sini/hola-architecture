let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  # Identity custom engine (seam test only)
  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = args: prev.modules.evalModules args;
    };
  });

  mkSys = lib: (import ~/Documents/repos/nixpkgs/nixos/lib/eval-config.nix {
    inherit lib;
    system = "x86_64-linux";
    modules = [
      { boot.isContainer = true;
        system.stateVersion = "24.05";
        fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
        boot.loader.grub.enable = false;
      }
    ];
  });

  real = mkSys realLib;
  cust = mkSys customLib;

  # Compare a meaningful slice of the FULL baseModules eval under both engines.
  pick = s: {
    hostName = s.config.networking.hostName;
    stateVersion = s.config.system.stateVersion;
    # attrsOf-submodule at scale: count systemd services, sample one
    nServices = builtins.length (builtins.attrNames s.config.systemd.services);
    # a deep merged value subject to mkMerge/priorities:
    sysctl = s.config.boot.kernel.sysctl;
    nOptions = builtins.length (builtins.attrNames s.options);
  };
in {
  parity =
    let r = pick real; c = pick cust;
    in {
      hostNameEq = r.hostName == c.hostName;
      stateEq = r.stateVersion == c.stateVersion;
      nServicesEq = r.nServices == c.nServices;
      sysctlEq = r.sysctl == c.sysctl;
      nOptionsEq = r.nOptions == c.nOptions;
      nServices = r.nServices;
      nOptions = r.nOptions;
    };
}
