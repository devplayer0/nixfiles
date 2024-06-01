{ lib, pkgs, config, ... }:
let
  inherit (builtins) isPath;
  inherit (lib) mkIf isStorePath;
  inherit (lib.options) mkOption mkEnableOption;
  jsonFormat = pkgs.formats.json { };

  swayncConfig = with lib.types; submodule {
    freeformType = jsonFormat.type;

    options = {
      "$schema" = mkOption {
        type = str;
        default = "${cfg.package}/etc/xdg/configSchema.json";
        description = ''
          Path to schema for config.
        '';
      };
    };
  };

  cfg = config.my.swaync;
in
{
  options.my.swaync = with lib.types; {
    enable = mkEnableOption "Sway Notification Center";
    package = mkOption {
      type = package;
      default = pkgs.swaynotificationcenter;
      defaultText = literalExpression "pkgs.swaynotificationcenter";
      description = ''
        swaync package to use. Set to <code>null</code> to use the default package.
      '';
    };

    settings = mkOption {
      type = swayncConfig;
      default = { };
      description = ''
        Configuration for Sway Notification Center, see swaync(1) for details.
      '';
    };

    style = mkOption {
      type = nullOr (either path str);
      default = null;
      description = ''
        CSS styling for Sway Notification Center. If set to a path literal, this will be used
        instead of writing the string to a file.
      '';
    };
  };

  config =
  let
    configSource = jsonFormat.generate "swaync.json" cfg.settings;
    styleSource = if isPath cfg.style || isStorePath cfg.style then
      cfg.style
    else
      pkgs.writeText "swaync.css" cfg.style;
  in
  mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg = {
      # swaync _really_ wants to pull the CSS from the system config dir
      systemDirs.config = [ "${cfg.package}/etc/xdg" ];

      configFile = {
        "swaync/config.json" = mkIf (cfg.settings != { }) {
          source = configSource;
          onChange = ''
            if ${pkgs.systemd}/bin/systemctl --user is-active --quiet swaync; then
              ${cfg.package}/bin/swaync-client --reload-config
            fi
          '';
        };
        "swaync/style.css" = mkIf (cfg.style != null) {
          source = styleSource;
          onChange = ''
            if ${pkgs.systemd}/bin/systemctl --user is-active --quiet swaync; then
              ${cfg.package}/bin/swaync-client --reload-css
            fi
          '';
        };
      };
    };

    systemd.user.services.swaync = {
      Unit = {
        Description = "Swaync notification daemon";
        Documentation = "https://github.com/ErikReider/SwayNotificationCenter";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };

      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = "${cfg.package}/bin/swaync";
        ExecReload = "${cfg.package}/bin/swaync-client --reload-config ; ${cfg.package}/bin/swaync-client --reload-css";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
