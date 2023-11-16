{ lib, ... }:
let
  inherit (lib) mkForce mkMerge;
  inherit (lib.my) net;
  inherit (lib.my.c.kelder) domain prefixes;
in
{
  nixos.systems.kelder-spoder = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "spoder-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 3 prefixes.ctrs.v4;
      };
    };

    configuration = { lib, pkgs, config, assignments, ... }:
    let
      inherit (lib.my) networkdAssignment;
    in
    {
      imports = [ ./nginx.nix ];

      config = {
        my = {
          deploy.enable = false;
          server.enable = true;
          user.config.name = "kontent";

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBdYyebQv/bBLbat1Csnr1/VMPKsi99PiLOXyKeQb7oX";
            files = {
              "kelder/cloudflare-credentials.conf" = {
                owner = "acme";
                group = "acme";
              };
              "kelder/nextcloud-root.txt" = {
                owner = "nextcloud";
                group = "nextcloud";
              };
            };
          };
        };

        security.acme = {
          acceptTerms = true;
          defaults = {
            email = "dev@nul.ie";
            server = "https://acme-v02.api.letsencrypt.org/directory";
            reloadServices = [ "nginx" ];
            dnsResolver = "8.8.8.8";
          };
          certs = {
            "${domain}" = {
              extraDomainNames = [
                "*.${domain}"
              ];
              dnsProvider = "cloudflare";
              credentialsFile = config.age.secrets."kelder/cloudflare-credentials.conf".path;
            };
          };
        };

        users = {
          groups.storage.gid = lib.my.c.kelder.groups.storage;
          users = {
            nginx.extraGroups = [ "acme" ];

            "${config.my.user.config.name}".extraGroups = [ "storage" ];
          };
        };

        systemd = {
          network.networks."80-container-host0" = mkMerge [
            (networkdAssignment "host0" assignments.internal)
            {
              linkConfig.MTUBytes = "1420";
            }
          ];
          services = {
            radarr.serviceConfig.UMask = "0002";
            sonarr.serviceConfig.UMask = "0002";
          };
        };

        services = {
          resolved.extraConfig = mkForce "";

          nextcloud = {
            enable = true;
            package = pkgs.nextcloud27;
            datadir = "/mnt/storage/nextcloud";
            hostName = "cloud.${domain}";
            https = true;
            config = {
              extraTrustedDomains = [ "cloud-local.${domain}" ];
              adminpassFile = config.age.secrets."kelder/nextcloud-root.txt".path;
              defaultPhoneRegion = "IE";
            };
            extraOptions = {
              updatechecker = false;
            };
          };
        };
      };
    };
  };
}
