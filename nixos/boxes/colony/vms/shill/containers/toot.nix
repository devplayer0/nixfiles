{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.colony) domain prefixes;
in
{
  nixos.systems.toot = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "toot-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 8 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::8";
          address = net.cidr.host 8 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib) mkMerge mkIf genAttrs;
      inherit (lib.my) networkdAssignment systemdAwaitPostgres;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILSslLkDe54AKYzxdtKD70zcU72W0EpYsfbdJ6UFq0QK";
              files = genAttrs
                (map (f: "toot/${f}") [
                  "postgres-password.txt"
                  "secret-key.txt"
                  "otp-secret.txt"
                  "vapid-key.txt"
                  "smtp-password.txt"
                  "s3-secret-key.txt"
                ])
                (_: with config.services.mastodon; {
                  owner = user;
                  inherit group;
                });
            };

            firewall = {
              tcp.allowed = [
                19999

                config.services.mastodon.webPort
                config.services.mastodon.streamingPort
              ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
            services = {
              # No option to provide an S3 secret access key file :(
              mastodon-init-dirs.script = ''
                echo "AWS_SECRET_ACCESS_KEY=\""$(< ${config.age.secrets."toot/s3-secret-key.txt".path})"\"" >> /var/lib/mastodon/.secrets_env
              '';
              mastodon-init-db = systemdAwaitPostgres pkgs.postgresql "colony-psql";

              # Can't use the extraConfig because these services expect a different format for the both family bind address...
              mastodon-streaming.environment.BIND = "::";
              mastodon-web.environment.BIND = "[::]";
            };
          };

          services = {
            netdata.enable = true;
            mastodon = mkMerge [
              {
                enable = true;
                localDomain = "nul.ie";
                extraConfig.WEB_DOMAIN = "toot.nul.ie";

                secretKeyBaseFile = config.age.secrets."toot/secret-key.txt".path;
                otpSecretFile = config.age.secrets."toot/otp-secret.txt".path;
                vapidPrivateKeyFile = config.age.secrets."toot/vapid-key.txt".path;
                vapidPublicKeyFile = toString (pkgs.writeText
                  "vapid-pubkey.txt"
                  "BAyRyD2pnLQtMHr3J5AzjNMll_HDC6ra1ilOLAUmKyhkEdbm7_OwKZUgw1UefY4CHEcv4OOX9TnnN2DOYYuPZu8=");

                enableUnixSocket = false;
                configureNginx = false;
                trustedProxy = allAssignments.middleman.internal.ipv6.address;

                database = {
                  createLocally = false;
                  host = "colony-psql";
                  user = "mastodon";
                  passwordFile = config.age.secrets."toot/postgres-password.txt".path;
                  name = "mastodon";
                };

                smtp = {
                  createLocally = false;
                  fromAddress = "Mastodon <toot@nul.ie>";
                  host = "mail.nul.ie";
                  port = 587;
                  authenticate = true;
                  user = "toot@nul.ie";
                  passwordFile = config.age.secrets."toot/smtp-password.txt".path;
                };
                extraConfig.SMTP_ENABLE_STARTTLS_AUTO = "true";

                redis.createLocally = true;

                mediaAutoRemove = {
                  enable = true;
                  olderThanDays = 30;
                };
              }
              {
                extraConfig = {
                  S3_ENABLED = "true";
                  S3_BUCKET = "mastodon";
                  AWS_ACCESS_KEY_ID = "mastodon";
                  S3_ENDPOINT = "https://s3.nul.ie/";
                  S3_REGION = "eu-central-1";
                  S3_PROTOCOL = "https";
                  S3_HOSTNAME = "mastodon.s3.nul.ie";

                  S3_ALIAS_HOST = "mastodon.s3.nul.ie";
                };
              }
            ];
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = with config.services.mastodon; [
              { from = "host"; guest.port = webPort; }
              { from = "host"; guest.port = streamingPort; }
            ];
          };
        })
      ];
    };
  };
}
