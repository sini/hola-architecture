# End-to-end through nixos eval-config-minimal -> lib.evalModules with overlay.
# Does the overlay's lib.evalModules fire for the ROOT nixos eval,
# and does it fire for a systemd.services-style attrsOf submodule element?
let
  realLib = import /home/sini/Documents/repos/nixpkgs/lib;
  mkCustomLib = realLib.extend (final: prev: {
    evalModules = args:
      builtins.trace "OVR lib.evalModules class=${toString (args.class or null)} nmods=${toString (builtins.length (args.modules or []))}"
      (prev.evalModules args);
    modules = prev.modules // {
      evalModules = args:
        builtins.trace "OVR modules.evalModules class=${toString (args.class or null)} prefix=[${toString (args.prefix or [])}]"
        (prev.modules.evalModules args);
    };
  });

  nixosLib = import /home/sini/Documents/repos/nixpkgs/nixos/lib { lib = mkCustomLib; };

  # Minimal module set with an attrsOf-submodule that mimics systemd.services
  cfg = nixosLib.evalModules {
    modules = [
      ({ lib, ... }: {
        options.svc = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {
            options.enable = lib.mkOption { type = lib.types.bool; default = false; };
          });
          default = {};
        };
        config.svc.web.enable = true;
        config.svc.db.enable = true;
      })
    ];
  };
in builtins.deepSeq [ cfg.config.svc.web.enable cfg.config.svc.db.enable ] "DONE"
