{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.kelder) domain prefixes;
in
{
  nixos.systems.kelder-acquisition = { config, ...}: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "acquisition-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 2 prefixes.ctrs.v4;
      };
    };

    configuration = { lib, pkgs, config, ... }:
    let
      inherit (lib);
    in
    {
      imports = [ ./networking.nix ];

      config = {
        # Hardware acceleration for Jellyfin
        hardware.opengl = {
          enable = true;
          extraPackages = with pkgs; [
            vaapiIntel
            intel-ocl
          ];
        };

        my = {
          deploy.enable = false;
          server.enable = true;
          user.config.name = "kontent";

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILSJ8d0prcSvyYi0UasnxMk/HGF5lWZz/t/VFYgQuFwO";
          };
        };

        users = {
          groups.media.gid = lib.my.c.kelder.groups.media;
          users = {
            "${config.my.user.config.name}".extraGroups = [ "media" ];

            transmission.extraGroups = [ "media" ];
            radarr.extraGroups = [ "media" ];
            sonarr.extraGroups = [ "media" ];
            jellyfin.extraGroups = [ "render" ];
          };
        };

        environment.systemPackages = with pkgs; [
          libva-utils
          clinfo
          jellyfin-ffmpeg
        ];

        systemd = {
          services = {
            jackett.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];

            transmission.bindsTo = [ "systemd-networkd-wait-online@vpn.service" ];
            # https://github.com/NixOS/nixpkgs/issues/258793#issuecomment-1748168206
            transmission.serviceConfig = {
              RootDirectoryStartOnly = lib.mkForce false;
              RootDirectory = lib.mkForce "";
            };

            radarr.serviceConfig.UMask = "0002";
            sonarr.serviceConfig.UMask = "0002";
          };
        };

        services = {
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

              speed-limit-down = 20480;
              speed-limit-down-enabled = true;
              speed-limit-up = 1024;
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
