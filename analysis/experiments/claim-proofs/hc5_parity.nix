let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  # A "custom engine" that is a TRANSPARENT passthrough (the only honest baseline
  # for a parity harness: a real reimplementation must diff against this identity).
  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = args: prev.modules.evalModules args;  # identity wrapper
    };
  });

  sharedModules = [
    ({ lib, ... }: {
      options.prio = lib.mkOption { type = lib.types.int; default = 0; };
      options.order = lib.mkOption { type = lib.types.listOf lib.types.str; default = []; };
      options.svc = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options.who = lib.mkOption { type = lib.types.str; default = name; };
          options.enable = lib.mkOption { type = lib.types.bool; default = false; };
        }));
        default = {};
      };
    })
    ({ lib, ... }: { config.prio = lib.mkDefault 1; })
    ({ lib, ... }: { config.prio = lib.mkForce 99; })          # mkForce
    ({ lib, ... }: { config.order = lib.mkOrder 1500 [ "b" ]; })
    ({ lib, ... }: { config.order = lib.mkOrder 500 [ "a" ]; }) # mkOrder
    { config.svc.web.enable = true; }                           # attrsOf-submodule + name-arg
    { config.svc.db = {}; }
  ];

  realEval = realLib.evalModules { modules = sharedModules; };
  custEval = customLib.evalModules { modules = sharedModules; };

  pick = e: {
    prio = e.config.prio;
    order = e.config.order;
    svcWho = builtins.mapAttrs (_: v: { inherit (v) who enable; }) e.config.svc;
    optionNames = builtins.attrNames e.options;
    # getSubOptions on the svc attrsOf-submodule:
    subOptNames = builtins.attrNames (e.options.svc.type.getSubOptions [ "svc" "*" ]);
  };

  r = pick realEval;
  c = pick custEval;
in {
  configDiffEmpty = (r.prio == c.prio) && (r.order == c.order) && (r.svcWho == c.svcWho);
  optionNamesEqual = r.optionNames == c.optionNames;
  getSubOptionsIdentical = r.subOptNames == c.subOptNames;
  # Show the actual resolved values to prove merge algebra ran:
  resolvedPrio = r.prio;        # mkForce 99 should win
  resolvedOrder = r.order;      # mkOrder => ["a" "b"]
  resolvedSvc = r.svcWho;       # name-arg: web/db; web.enable=true
}
