{ config, lib, ... }:
  let
    inherit (lib) mkIf;
    inherit (lib.my) mkBoolOpt;
  in {
    options.my.server.enable = mkBoolOpt false;
    config = mkIf config.my.server.enable {
      services.getty.autologinUser = config.my.user.name;
    };
  }
