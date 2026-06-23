let
  adios = import /home/sini/Documents/repos/adios/adios/default.nix;
  types = import /home/sini/Documents/repos/adios/adios/types.nix {
    korora = import /home/sini/Documents/repos/adios/types/types.nix;
  };
  tree = adios {
    name = "root";
    modules = {
      a = {
        name = "a";
        options.greeting = { type = types.string; default = "hello"; };
        impl = { options }: { msg = options.greeting; };
      };
    };
  } { options = { "/a" = { greeting = "first"; }; }; };
in
  tree.modules.a.args.options.greeting
