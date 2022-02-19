{ config, lib, ... }:
let
  inherit (lib) mkIf mkDefault;
  inherit (lib.my) mkBoolOpt';

  cfg = config.my.server;
  uname = if config.my.user.enable then config.my.user.config.name else "root";
in
{
  options.my.server.enable = mkBoolOpt' false "Whether to enable common configuration for servers.";
  config = mkIf cfg.enable {
    services = {
      getty.autologinUser = mkDefault uname;
      kmscon.autologinUser = mkDefault uname;
    };

    my.user.homeConfig = {
      my.gui.enable = false;
    };
  };

  meta.buildDocsInSandbox = false;
}
