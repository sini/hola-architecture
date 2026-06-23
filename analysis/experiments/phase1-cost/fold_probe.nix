let r = import /home/sini/Documents/repos/gen-algebra/pure/rec.nix;
in {
  append = (r.foldLayers { strategies.foo = "append";
    layers = [ {foo=["a"];} {foo=["z"];} {foo=["b"];} {foo=["c"];} ]; }).foo;
  replace = (r.foldLayers { strategies.foo = "replace";
    layers = [ {foo=["a"];} {foo=["z"];} {foo=["b"];} {foo=["c"];} ]; }).foo;
}
