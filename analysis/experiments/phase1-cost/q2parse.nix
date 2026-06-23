{ config, lib, pkgs, ... }: {
  config.services.foo.enable = config.services.bar.enable;
}
