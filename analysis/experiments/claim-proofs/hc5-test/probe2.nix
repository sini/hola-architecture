# Distinguish: does the OVERRIDE BODY execute per submodule element,
# or does it run once (for `base`) and ride along via internal extendModules?
let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;

  # The override appends a module that records a UNIQUE marker derived from
  # the modules-count it sees AT OVERRIDE-CALL TIME. If the override body runs
  # for each element eval, the per-element config sees a marker computed from
  # the element's own module list. If it runs only for `base`, every element
  # sees the SAME base-time marker (the override never re-ran for the element).
  #
  # Even sharper: append a builtins.trace so we can COUNT override-body entries.
  mkCustomLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = args:
        builtins.trace "OVERRIDE-ENTER modules.evalModules nmods=${toString (builtins.length (args.modules or []))} prefix=${toString (args.prefix or [])}"
        (prev.modules.evalModules args);
    };
    evalModules = args:
      builtins.trace "OVERRIDE-ENTER lib.evalModules nmods=${toString (builtins.length (args.modules or []))}"
      (prev.evalModules args);
  });

  testModule = { lib, ... }: {
    options.svc = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options.enable = lib.mkOption { type = lib.types.bool; default = false; };
      }));
      default = {};
    };
    config.svc.aaa.enable = true;
    config.svc.bbb.enable = true;
    config.svc.ccc.enable = false;
  };

  customEval = mkCustomLib.evalModules { modules = [ testModule ]; };
in
  # Force the three element configs so any per-element eval would fire.
  builtins.deepSeq [
    customEval.config.svc.aaa.enable
    customEval.config.svc.bbb.enable
    customEval.config.svc.ccc.enable
  ] "DONE"
