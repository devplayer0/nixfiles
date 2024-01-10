{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mkDefault;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.services.wastebin;
in
{
  options.services.wastebin = with lib.types; {
    enable = mkBoolOpt' false "Whether to enable wastebin.";
    package = mkOpt' package pkgs.wastebin "Package to use.";
    settings = mkOpt' (attrsOf str) { } "Environment variable settings.";
    extraSettingsFile = mkOpt' (nullOr str) null "Extra environment file (e.g. for signing key).";
  };

  config = mkIf cfg.enable {
    services.wastebin.settings = {
      WASTEBIN_ADDRESS_PORT = mkDefault "[::]:8088";
      WASTEBIN_DATABASE_PATH = mkDefault "/var/lib/wastebin/db.sqlite3";
    };

    systemd.services.wastebin = {
      description = "wastebin minimal pastebin";
      after = [ "network.target" ];
      environment = cfg.settings;
      serviceConfig = {
        EnvironmentFile = mkIf (cfg.extraSettingsFile != null) cfg.extraSettingsFile;
        DynamicUser = true;
        StateDirectory = "wastebin";
        ExecStart = "${cfg.package}/bin/wastebin";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
