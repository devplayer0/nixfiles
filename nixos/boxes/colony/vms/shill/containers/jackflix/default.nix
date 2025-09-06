{ lib, ... }:
let
  inherit (lib) concatStringsSep;
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.jackflix = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "jackflix-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 6 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::6";
          address = net.cidr.host 6 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib) mkForce;
    in
    {
      imports = [ ./networking.nix ];

      config = {
        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPUv1ntVrZv5ripsKpcOAnyDQX2PHjowzyhqWK10Ml53";
            files = {
              "jackflix/photoprism-pass.txt" = {};
            };
          };
        };

        users = with lib.my.c.ids; {
          users = {
            "${config.my.user.config.name}".extraGroups = [ "media" ];

            transmission.extraGroups = [ "media" ];
            radarr.extraGroups = [ "media" ];
            sonarr.extraGroups = [ "media" ];
            jellyseerr = {
              isSystemUser = true;
              uid = uids.jellyseerr;
              group = "jellyseerr";
            };
            photoprism = {
              isSystemUser = true;
              uid = uids.photoprism;
              group = "photoprism";
            };
          };
          groups = {
            media.gid = 2000;
            jellyseerr.gid = gids.jellyseerr;
            photoprism.gid = gids.photoprism;
          };
        };

        systemd = {
          services = {
            jackett.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];
            transmission.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];

            radarr.serviceConfig.UMask = "0002";
            sonarr.serviceConfig.UMask = "0002";
            jellyseerr.serviceConfig = {
              # Needs to be able to read its secrets
              DynamicUser = mkForce false;
              User = "jellyseerr";
              Group = "jellyseerr";
            };

            # https://github.com/NixOS/nixpkgs/issues/258793#issuecomment-1748168206
            transmission.serviceConfig = {
              RootDirectoryStartOnly = lib.mkForce false;
              RootDirectory = lib.mkForce "";
            };
            photoprism.serviceConfig = {
              # Needs to be able to access its data
              DynamicUser = mkForce false;
            };
          };
        };

        nixpkgs.config.permittedInsecurePackages = [
          # FIXME: This is needed for Sonarr
          "aspnetcore-runtime-wrapped-6.0.36"
          "aspnetcore-runtime-6.0.36"
          "dotnet-sdk-wrapped-6.0.428"
          "dotnet-sdk-6.0.428"
        ];

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

          flaresolverr.enable = true;
          jackett.enable = true;
          radarr.enable = true;
          sonarr.enable = true;
          jellyseerr = {
            enable = true;
            openFirewall = true;
          };

          jellyfin.enable = true;

          photoprism = {
            enable = true;
            address = "[::]";
            port = 2342;
            originalsPath = "/mnt/media/photoprism/originals";
            importPath = "/mnt/media/photoprism/import";
            passwordFile = config.age.secrets."jackflix/photoprism-pass.txt".path;
            settings = {
              PHOTOPRISM_AUTH_MODE = "password";
              PHOTOPRISM_ADMIN_USER = "dev";
              PHOTOPRISM_APP_NAME = "/dev/player0 Photos";
              PHOTOPRISM_SITE_URL = "https://photos.${pubDomain}/";
              PHOTOPRISM_SITE_TITLE = "/dev/player0 Photos";
              PHOTOPRISM_TRUSTED_PROXY = concatStringsSep "," (with prefixes.ctrs; [ v4 v6 ]);
              PHOTOPRISM_DATABASE_DRIVER = "sqlite";
            };
          };
        };
      };
    };
  };
}
