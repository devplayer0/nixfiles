{ config, lib, ... }:
let
  inherit (lib) mkIf;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.server;
in
{
  options.my.server.enable = mkBoolOpt' false "Whether to enable common configuration for servers.";
  config = mkIf cfg.enable {
    services = {
      getty.autologinUser = config.my.user.name;
      kmscon.autologinUser = config.my.user.name;
    };

    my.homeConfig = {
      my.gui.enable = false;
    };
  };

  meta.buildDocsInSandbox = false;
}
