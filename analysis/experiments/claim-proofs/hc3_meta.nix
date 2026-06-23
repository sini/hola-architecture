let
  lib = import /home/sini/Documents/repos/nixpkgs/lib;
  inherit (lib) evalModules mkForce mkDefault;
  e = evalModules { modules = [
    { options.p = lib.mkOption { type = lib.types.listOf lib.types.int; }; }
    { config.p = [ 1 ]; }
    { config.p = [ 2 ]; }
  ]; };
  # Does options.p expose valueMeta from v2 merge? Check options.p.value vs the internal
  opt = e.options.p;
in {
  value = e.config.p;
  hasValueMeta = opt ? valueMeta;
  metaKeys = if opt ? valueMeta then builtins.attrNames opt.valueMeta else [];
  optKeys = builtins.attrNames opt;
}
