let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  # Sentinel: a wrapper evalModules that tags every result
  customEvalModules = origEval: args:
    let r = origEval args;
    in r // { __customEngineRan = true; };

  # The "two-attr" injection HC5 describes
  customLib = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = customEvalModules prev.modules.evalModules;
    };
    evalModules = final.modules.evalModules;  # the alias HC5 claims you also need
  });

  # Does the top-level alias follow automatically WITHOUT the explicit second attr?
  customLibNoAlias = realLib.extend (final: prev: {
    modules = prev.modules // {
      evalModules = customEvalModules prev.modules.evalModules;
    };
  });
in {
  topAliasUpdated_withExplicit = customLib.evalModules ? __customEngineRan == false; # placeholder
  # Test: is the top-level evalModules alias the custom one even WITHOUT explicit alias attr?
  aliasFollowsAutomatically =
    let res = customLibNoAlias.evalModules { modules = []; };
    in res.__customEngineRan or false;
  # Test: does modules.evalModules get the override
  modulesEvalOverridden =
    let res = customLibNoAlias.modules.evalModules { modules = []; };
    in res.__customEngineRan or false;
}
