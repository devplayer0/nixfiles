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
      inherit (lib) mkMerge mkIf;
    in
    {
      imports = [ ./networking.nix ];

      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKzzAqa4821NlYfALYOlvR7YlOgxNuulTWo9Vm5L1mNU";
            };
          };

          users = {
            groups.media.gid = 2000;
            users = {
              transmission.extraGroups = [ "media" ];
              radarr.extraGroups = [ "media" ];
            };
          };

          systemd = {
            services = {
              radarr.serviceConfig.UMask = "0002";
            };
          };

          services = {
            transmission = {
              enable = true;
              openPeerPorts = true;
              openRPCPort = true;
              downloadDirPermissions = null;
              performanceNetParameters = true;
              settings = {
                download-dir = "/mnt/media/downloads/torrents";
                incomplete-dir-enabled = true;
                incomplete-dir = "/mnt/media/downloads/torrents/.incomplete";
                umask = 002;

                peer-port = 55471;
                utp-enabled = true;
                port-forwarding-enabled = false;

                ratio-limit = 2.0;
                ratio-limit-enabled = true;

                rpc-bind-address = "::";
                rpc-whitelist-enabled = false;
                rpc-host-whitelist-enabled = false;
              };
            };

            jackett = {
              enable = true;
              openFirewall = true;
            };
            radarr = {
              enable = true;
              openFirewall = true;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 9117; guest.port = 9117; }
              { from = "host"; host.port = 7878; guest.port = 7878; }
              { from = "host"; host.port = 8989; guest.port = 8989; }
            ];
          };
        })
      ];
    };
  };
}
