{ lib, ...}: {
  nixos.systems.vaultwarden = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "vaultwarden-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}3";
        ipv6 = {
          iid = "::3";
          address = "${lib.my.colony.start.ctrs.v6}3";
        };
      };
    };

    configuration = { lib, config, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;

      vwData = "/var/lib/vaultwarden";
      vwSecrets = "vaultwarden.env";
    in
    {
      config = mkMerge [
        {
          my = {
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILakffcjRp6h6lxSOADOsTK5h2MCkt8hKDv0cvchM7iw";
              files."${vwSecrets}" = {};
            };

            firewall = {
              tcp.allowed = [ 80 3012 ];
            };

            tmproot.persistence.config.directories = [
              {
                directory = vwData;
                user = config.users.users.vaultwarden.name;
                group = config.users.groups.vaultwarden.name;
              }
            ];
          };

          systemd = {
            services.vaultwarden.serviceConfig.StateDirectory = mkForce "vaultwarden";
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            vaultwarden = {
              enable = true;
              config = {
                dataFolder = vwData;
                webVaultEnabled = true;

                rocketPort = 80;
                websocketEnabled = true;
                websocketPort = 3012;
              };
              environmentFile = config.age.secrets."${vwSecrets}".path;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 8080; guest.port = 80; }
            ];
          };
        })
      ];
    };
  };
}