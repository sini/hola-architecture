let
  mk = import /home/sini/Documents/repos/gen-algebra/pure/rec.nix;
  rec' = mk { self = rec'; };
in
  (rec'.foldLayers {
    strategies.foo = "replace";
    layers = [
      { foo = [ "a" ]; }   # mkOrder 100
      { foo = [ "z" ]; }   # mkDefault
      { foo = [ "b" ]; }   # mkIf true
      { foo = [ "c" ]; }   # mkForce
    ];
  }).foo
