let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkOrder mkBefore mkAfter mkMerge mkOverride;
  ev = mods: (evalModules { modules = mods; }).config;
  # I1: mkOrder wrapping mkForce vs mkForce wrapping mkOrder - nesting order of properties
  # filterOverrides runs on dischargeProperties output; mkOrder is NOT discharged, NOT filtered (it's sorted later)
  # So mkForce(mkOrder x) : override wraps order -> dischargeProperties sees "override"? No: dischargeProperties only handles merge/if. override survives to filterOverrides. getPrio reads .value._type=="override" -> prio 50. strip -> content = mkOrder x. Then sortProperties sees "order".
  nest1 = (ev [
    { options.x = lib.mkOption { type = lib.types.lines; }; }
    { config.x = "plain"; }
    { config.x = mkForce (mkOrder 100 "forced-early"); }
  ]).x;
  # I2: the reverse: mkOrder(mkForce x). getPrio: .value._type=="order" -> NOT override -> default prio 100. So this def is at prio 100, the mkForce inside is hidden from filterOverrides!
  nest2 = (ev [
    { options.y = lib.mkOption { type = lib.types.lines; }; }
    { config.y = "plain"; }
    { config.y = mkOrder 100 (mkForce "ordered-force"); }
  ]).y;
in { inherit nest1 nest2; }
