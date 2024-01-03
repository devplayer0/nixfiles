{ lib, pkgs, config, ... }:
let
  inherit (builtins) toJSON;
  inherit (lib) mkOption mkMerge mkIf mkDefault;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.librespeed;

  serversConf = map (s: s // {
    dlURL = "backend/garbage";
    ulURL = "backend/empty";
    pingURL = "backend/empty";
    getIpURL = "backend/getIP";
  }) cfg.frontend.servers;
  frontendTree = pkgs.runCommand "librespeed-frontend" {
    speedtestServers = toJSON serversConf;
  } ''
    mkdir "$out"
    cp "${pkgs.librespeed-go}"/assets/* "$out"/
    substitute ${./index.html} "$out"/index.html --subst-var speedtestServers
  '';

  backendConf = pkgs.writers.writeTOML "librespeed.toml" cfg.backend.settings;
  generateBackendSettings = base: dst: if (cfg.backend.extraSettingsFile != null) then ''
    oldUmask="$(umask)"
    umask 006
    cat "${base}" "${cfg.backend.extraSettingsFile}" > "${dst}"
    umask "$oldUmask"
  '' else ''
    cp "${base}" "${dst}"
  '';
in
{
  options.my.librespeed = with lib.types; {
    frontend = {
      servers = mkOpt' (listOf (attrsOf unspecified)) { } "Server configs.";
      webroot = mkOption {
        description = "Frontend webroot.";
        type = package;
        readOnly = true;
      };
    };
    backend = {
      enable = mkBoolOpt' false "Whether to enable librespeed backend.";
      settings = mkOpt' (attrsOf unspecified) { } "Backend settings.";
      extraSettingsFile = mkOpt' (nullOr str) null "Extra settings file.";
    };
  };

  config = mkMerge [
    (mkIf (cfg.frontend.servers != { }) {
      my.librespeed.frontend.webroot = frontendTree;
    })
    (mkIf cfg.backend.enable {
      my.librespeed.backend.settings = {
        assets_path = frontendTree;
        database_type = mkDefault "bolt";
        database_file = mkDefault "/var/lib/librespeed-go/speedtest.db";
      };

      systemd.services.librespeed = {
        description = "LibreSpeed Go backend";
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];

        preStart = generateBackendSettings backendConf "/run/librespeed-go/settings.toml";
        serviceConfig = {
          ExecStart = "${pkgs.librespeed-go}/bin/speedtest -c /run/librespeed-go/settings.toml";
          RuntimeDirectory = "librespeed-go";
          StateDirectory = "librespeed-go";
        };
        wantedBy = [ "multi-user.target" ];
      };
    })
  ];
}
