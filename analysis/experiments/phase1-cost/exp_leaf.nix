let e = import /tmp/mk_mod.nix {}; in builtins.deepSeq e.config.opt1 (builtins.length e.config.opt1)
