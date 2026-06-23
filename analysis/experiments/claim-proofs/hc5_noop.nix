let
  realLib = import ~/Documents/repos/nixpkgs/lib;

  # Override lib.types.submoduleWith to a POISONED version that throws.
  # If `submodule`/`attrsOf(submodule)` used lib.types.submoduleWith, this would throw.
  # If they use the LOCAL binding (NO-OP claim), it evaluates fine.
  poisonedLib = realLib.extend (final: prev: {
    types = prev.types // {
      submoduleWith = args: throw "POISONED submoduleWith CALLED";
      attrsOf = elemType: throw "POISONED attrsOf CALLED";
    };
  });

  result = poisonedLib.evalModules {
    modules = [
      ({ lib, ... }: {
        # Use the LOCAL realLib.types (as a real module would: it gets lib via _module.args).
        # But the module receives `lib` = poisonedLib. So `lib.types.attrsOf` IS poisoned here.
        # To test the INTERNAL no-op, we must use a type built by the engine internally.
        # Real nixpkgs modules write `types.attrsOf (types.submodule ...)` -> uses poisonedLib.types -> WOULD throw.
        options.x = lib.mkOption {
          type = lib.types.submodule { options = {}; };  # poisonedLib.types.submodule -> uses LOCAL submoduleWith?
          default = {};
        };
      })
      { x = {}; }
    ];
  };
in {
  evaluated = builtins.deepSeq result.config.x true;
}
