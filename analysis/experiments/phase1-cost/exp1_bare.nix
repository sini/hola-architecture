let pkgs = import ~/Documents/repos/nixpkgs {}; in builtins.length (builtins.attrNames pkgs)
