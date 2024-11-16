{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.vaultwarden = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

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
              files = {
                "vaultwarden/config.env" = {};
                "vaultwarden/backup-pass.txt" = {};
                "vaultwarden/backup-ssh.key" = {};
              };
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

          programs.ssh.knownHostsFiles = [
            lib.my.c.sshKeyFiles.rsyncNet
          ];

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

                DOMAIN = "https://pass.${lib.my.c.pubDomain}";

                ROCKET_ADDRESS = "::";
                ROCKET_PORT = 8080;

                SMTP_HOST = "mail.nul.ie";
                SMTP_FROM = "pass@nul.ie";
                SMTP_FROM_NAME = "Vaultwarden";
                SMTP_SECURITY = "starttls";
                SMTP_PORT = 587;
                SMTP_USERNAME = "pass@nul.ie";
                SMTP_TIMEOUT = 15;

                PUSH_ENABLED = true;
              };
              environmentFile = config.age.secrets."vaultwarden/config.env".path;
            };

            borgbackup.jobs.vaultwarden = {
              readWritePaths = [ "/var/lib/borgbackup" "/var/cache/borgbackup" ];

              paths = [ vwData ];
              repo = "zh2855@zh2855.rsync.net:borg/vaultwarden2";
              doInit = true;
              environment = {
                BORG_REMOTE_PATH = "borg1";
                BORG_RSH = ''ssh -i ${config.age.secrets."vaultwarden/backup-ssh.key".path}'';
              };
              compression = "zstd,10";
              encryption = {
                mode = "repokey";
                passCommand = ''cat ${config.age.secrets."vaultwarden/backup-pass.txt".path}'';
              };
              prune.keep = {
                within = "1d";
                daily = 7;
                weekly = 4;
                monthly = -1;
              };
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
