let e = import /tmp/mk_mod.nix {}; in builtins.deepSeq e.config "done"
