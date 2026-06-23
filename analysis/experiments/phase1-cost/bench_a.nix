# Pure nixpkgs lib import, no module system, no package set
let np = import <nixpkgs> {}; in np.lib.version
