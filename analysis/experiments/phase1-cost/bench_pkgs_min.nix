# instantiate pkgs but force nothing beyond a trivial lib attr
let np = import <nixpkgs> { config = {}; overlays = []; }; in np.lib.version
