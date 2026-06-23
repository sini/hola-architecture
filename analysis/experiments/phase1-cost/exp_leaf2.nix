let e = import /tmp/mk_mod.nix {}; in builtins.seq e.config.opt1 e.config.opt1
