{ lib, pkgs, config, ... }:
let
  inherit (lib) mkIf mapAttrs;
  inherit (lib.my) mkOpt' mkBoolOpt';

  cfg = config.my.paseo-relay;
in
{
  options.my.paseo-relay = with lib.types; {
    enable = mkBoolOpt' false "Whether to enable the Paseo relay.";
    package = mkOpt' package pkgs.paseo-relay "Paseo relay package.";
    host = mkOpt' str "127.0.0.1" "Address to listen on.";
    port = mkOpt' port 4000 "Port to listen on (plain HTTP / WebSocket).";
    environment = mkOpt' (attrsOf (oneOf [ str int bool ])) { }
      "Extra `PASEO_RELAY_*` environment variables (see the relay's README).";
  };

  config = mkIf cfg.enable {
    systemd.services.paseo-relay = {
      description = "Paseo relay";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      environment = {
        PASEO_RELAY_HOST = cfg.host;
        PASEO_RELAY_PORT = toString cfg.port;
        # Single node: no Erlang distribution (and so no epmd)
        RELEASE_DISTRIBUTION = "none";
        RELEASE_TMP = "/run/paseo-relay";
        HOME = "/run/paseo-relay";
      } // mapAttrs (_: v: if v == true then "true" else if v == false then "false" else toString v)
        cfg.environment;

      # The release script requires a cookie even without distribution
      script = ''
        RELEASE_COOKIE="$(head -c 32 /dev/urandom | sha256sum | cut -d' ' -f1)"
        export RELEASE_COOKIE
        exec ${cfg.package}/bin/paseo_relay start
      '';

      serviceConfig = {
        DynamicUser = true;
        RuntimeDirectory = "paseo-relay";
        Restart = "always";
        RestartSec = 5;

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
