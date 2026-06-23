# Confirm per-element evals DO happen (so missing override traces = real gap, not laziness).
let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;
  mkCustomLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = args:
        builtins.trace "OVERRIDE modules.evalModules prefix=[${toString (args.prefix or [])}]"
        (prev.modules.evalModules args);
    };
  });
  testModule = { lib, ... }: {
    options.svc = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options.enable = lib.mkOption {
          type = lib.types.bool; default = false;
        };
        # Prove the ELEMENT body evaluates per element:
        config.enable = lib.mkDefault (builtins.trace "ELEMENT-EVAL name=${name}" false);
      }));
      default = {};
    };
    config.svc.aaa = {};
    config.svc.bbb = {};
  };
  customEval = mkCustomLib.evalModules { modules = [ testModule ]; };
in builtins.deepSeq [
     customEval.config.svc.aaa.enable
     customEval.config.svc.bbb.enable
   ] "DONE"
