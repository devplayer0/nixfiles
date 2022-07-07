{ lib, ... }: {
  nixos.systems.jackflix = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "jackflix-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}6";
        ipv6 = {
          iid = "::6";
          address = "${lib.my.colony.start.ctrs.v6}6";
        };
      };
    };

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib);
    in
    {
      imports = [ ./networking.nix ];

      config = {
        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPUv1ntVrZv5ripsKpcOAnyDQX2PHjowzyhqWK10Ml53";
          };
        };

        users = {
          groups.media.gid = 2000;
          users = {
            "${config.my.user.config.name}".extraGroups = [ "media" ];

            transmission.extraGroups = [ "media" ];
            radarr.extraGroups = [ "media" ];
            sonarr.extraGroups = [ "media" ];
          };
        };

        systemd = {
          services = {
            jackett.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];
            transmission.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];

            radarr.serviceConfig.UMask = "0002";
            sonarr.serviceConfig.UMask = "0002";
          };
        };

        services = {
          netdata.enable = true;

          transmission = {
            enable = true;
            downloadDirPermissions = null;
            performanceNetParameters = true;
            settings = {
              download-dir = "/mnt/media/downloads/torrents";
              incomplete-dir-enabled = true;
              incomplete-dir = "/mnt/media/downloads/torrents/.incomplete";
              umask = 002;

              utp-enabled = true;
              port-forwarding-enabled = false;

              speed-limit-down = 28160;
              speed-limit-down-enabled = true;
              speed-limit-up = 28160;
              speed-limit-up-enabled = true;
              ratio-limit = 2.0;
              ratio-limit-enabled = true;

              rpc-bind-address = "::";
              rpc-whitelist-enabled = false;
              rpc-host-whitelist-enabled = false;
            };
          };

          jackett.enable = true;
          radarr.enable = true;
          sonarr.enable = true;

          jellyfin.enable = true;
        };
      };
    };
  };
}
