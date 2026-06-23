let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;

  mkCustomLib = tag: realLib.extend (final: prev: {
    evalModules = args:
      prev.evalModules (args // {
        modules = (args.modules or []) ++ [
          ({ lib, ... }: {
            options._hc5_root_sentinel = lib.mkOption { type = lib.types.str; default = "UNSET"; };
            config._hc5_root_sentinel = lib.mkForce tag;
          })
        ];
      });
    modules = prev.modules // {
      evalModules = args:
        prev.modules.evalModules (args // {
          modules = (args.modules or []) ++ [
            ({ lib, ... }: {
              options._hc5_sub_sentinel = lib.mkOption { type = lib.types.str; default = "UNSET"; };
              config._hc5_sub_sentinel = lib.mkForce tag;
            })
          ];
        });
    };
  });

  customLib = mkCustomLib "CUSTOM";

  testModule = { lib, ... }: {
    options.svc = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options.enable = lib.mkOption { type = lib.types.bool; default = false; };
      }));
      default = {};
    };
    config.svc.foo.enable = true;
  };

  evalWith = lib: lib.evalModules { modules = [ testModule ]; };
  realEval   = evalWith realLib;
  customEval = evalWith customLib;
in {
  rootSentinelCustom = customEval.config._hc5_root_sentinel or "ABSENT";
  rootSentinelReal   = realEval.config._hc5_root_sentinel or "ABSENT";
  subSentinelCustom  = customEval.config.svc.foo._hc5_sub_sentinel or "ABSENT";
  fooEnable = customEval.config.svc.foo.enable;
}
