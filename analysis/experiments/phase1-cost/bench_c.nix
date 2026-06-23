# Force a small package: hello (exercises stdenv // storms but NOT module system)
let np = import <nixpkgs> {}; in np.hello.name
