let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  customEvalModules = origEval: args:
    origEval (args // {
      modules = (args.modules or []) ++ [
        { config._module.args.__sentinel = "CUSTOM_ENGINE"; }
      ];
    });

  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = customEvalModules prev.modules.evalModules;
    };
  });

  # Call eval-config.nix passing our CUSTOM lib.
  evalConfig = import ~/Documents/repos/nixpkgs/nixos/lib/eval-config.nix;

  sys = evalConfig {
    lib = customLib;
    system = "x86_64-linux";
    modules = [
      ({ __sentinel ? "NONE", lib, pkgs, ... }: {
        # minimal: just expose whether the sentinel arg arrived
        options.test.sawSentinel = lib.mkOption { type = lib.types.str; default = "NONE"; };
        config.test.sawSentinel = __sentinel;
        # neutralize the rest of NixOS so it evaluates cheaply
        config.boot.isContainer = true;
        config.system.stateVersion = "24.05";
        config.fileSystems."/".device = "none";
      })
    ];
  };
in {
  rootSawSentinel = sys.config.test.sawSentinel;
}
