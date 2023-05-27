{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.colony) domain prefixes;
in
{
  nixos.systems.vaultwarden = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "vaultwarden-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 3 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::3";
          address = net.cidr.host 3 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, config, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;

      vwData = "/var/lib/vaultwarden";
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFP2mF50ENpnJnr+VTnG9P+JFPjgwvoIxCLyJPzXRpVy";
              files."vaultwarden.env" = {};
            };

            firewall = {
              tcp.allowed = with config.services.vaultwarden.config; [ ROCKET_PORT WEBSOCKET_PORT ];
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
                DATA_FOLDER = vwData;

                WEB_VAULT_ENABLED = true;

                WEBSOCKET_ENABLED = true;
                WEBSOCKET_ADDRESS = "::";
                WEBSOCKET_PORT = 3012;

                SIGNUPS_ALLOWED = false;

                DOMAIN = "https://pass.${lib.my.pubDomain}";

                ROCKET_ADDRESS = "::";
                ROCKET_PORT = 80;

                SMTP_HOST = "mail.nul.ie";
                SMTP_FROM = "pass@nul.ie";
                SMTP_FROM_NAME = "Vaultwarden";
                SMTP_SECURITY = "starttls";
                SMTP_PORT = 587;
                SMTP_USERNAME = "pass@nul.ie";
                SMTP_TIMEOUT = 15;
              };
              environmentFile = config.age.secrets."vaultwarden.env".path;
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
