let e = import /tmp/mk_mod.nix {}; in builtins.length (builtins.attrNames e.config)
