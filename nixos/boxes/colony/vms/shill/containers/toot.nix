{ lib, ... }:
let
  inherit (lib) mkForce;
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.toot = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

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

      pdsPort = 3000;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILSslLkDe54AKYzxdtKD70zcU72W0EpYsfbdJ6UFq0QK";
              files = (genAttrs
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
                })) // {
                  "toot/pds.env" = {
                    owner = "pds";
                    group = "pds";
                  };
                };
            };

            firewall = {
              tcp.allowed = [
                19999

                "http"
                pdsPort
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
              rec {
                enable = true;
                localDomain = extraConfig.WEB_DOMAIN; # for nginx config
                extraConfig = {
                  LOCAL_DOMAIN = "nul.ie";
                  WEB_DOMAIN = "toot.nul.ie";
                };

                secretKeyBaseFile = config.age.secrets."toot/secret-key.txt".path;
                otpSecretFile = config.age.secrets."toot/otp-secret.txt".path;
                vapidPrivateKeyFile = config.age.secrets."toot/vapid-key.txt".path;
                vapidPublicKeyFile = toString (pkgs.writeText
                  "vapid-pubkey.txt"
                  "BAyRyD2pnLQtMHr3J5AzjNMll_HDC6ra1ilOLAUmKyhkEdbm7_OwKZUgw1UefY4CHEcv4OOX9TnnN2DOYYuPZu8=");

                streamingProcesses = 4;
                configureNginx = true;

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

            # Override some stuff since we are proxying upstream
            nginx = {
              recommendedProxySettings = mkForce false;
              virtualHosts."${config.services.mastodon.localDomain}" =
              let
                extraConfig = ''
                  proxy_set_header Host $host;
                '';
              in
              {
                forceSSL = false;
                enableACME = false;
                locations = {
                  "@proxy" = { inherit extraConfig; };
                  "/api/v1/streaming/" = { inherit extraConfig; };
                };
              };
            };

            pds = {
              enable = true;
              environmentFiles = [ config.age.secrets."toot/pds.env".path ];
              settings = {
                PDS_HOSTNAME = "pds.nul.ie";
                PDS_PORT = pdsPort;

                PDS_BLOBSTORE_DISK_LOCATION = null;
                PDS_BLOBSTORE_S3_BUCKET = "pds";
                PDS_BLOBSTORE_S3_ENDPOINT = "https://s3.nul.ie/";
                PDS_BLOBSTORE_S3_REGION = "eu-central-1";
                PDS_BLOBSTORE_S3_ACCESS_KEY_ID = "pds";
                PDS_BLOB_UPLOAD_LIMIT = "52428800";

                PDS_EMAIL_FROM_ADDRESS = "pds@nul.ie";

                PDS_DID_PLC_URL = "https://plc.directory";
                PDS_INVITE_REQUIRED = 1;
                PDS_BSKY_APP_VIEW_URL = "https://api.bsky.app";
                PDS_BSKY_APP_VIEW_DID = "did:web:api.bsky.app";
                PDS_REPORT_SERVICE_URL = "https://mod.bsky.app";
                PDS_REPORT_SERVICE_DID = "did:plc:ar7c4by46qjdydhdevvrndac";
                PDS_CRAWLERS = "https://bsky.network";
              };
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = with config.services.mastodon; [
              { from = "host"; guest.port = webPort; }
            ];
          };
        })
      ];
    };
  };
}
