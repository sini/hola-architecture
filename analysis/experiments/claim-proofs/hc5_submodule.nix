let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  # Custom engine injects a sentinel module into EVERY evalModules call,
  # so we can detect whether submodule recursion went through it.
  customEvalModules = origEval: args:
    origEval (args // {
      modules = (args.modules or []) ++ [
        { config._module.args.__sentinel = true; }
      ];
    });

  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = customEvalModules prev.modules.evalModules;
    };
  });

  result = customLib.evalModules {
    modules = [
      ({ lib, ... }: {
        options.svc = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule ({ __sentinel ? false, ... }: {
            options.sawSentinel = lib.mkOption { type = lib.types.bool; default = false; };
            config.sawSentinel = __sentinel;
          }));
          default = {};
        };
      })
      { svc.foo = {}; }
    ];
  };
in {
  # If submodule recursion went through customLib.modules.evalModules,
  # the injected __sentinel arg reaches the submodule element -> sawSentinel=true
  submoduleSawSentinel = result.config.svc.foo.sawSentinel;
}
