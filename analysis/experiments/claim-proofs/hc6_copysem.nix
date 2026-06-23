let
  mk = i: { name = "k" + toString i; value = throw "nf"; };
  big = builtins.listToAttrs (map mk (builtins.genList (x: x) 1000));
  merged = big // { extra = 1; } // { extra2 = 2; };
in builtins.length (builtins.attrNames merged)
