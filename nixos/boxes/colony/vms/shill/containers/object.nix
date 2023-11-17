{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.object = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "object-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 7 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::7";
          address = net.cidr.host 7 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (config.my.user.homeConfig.lib.file) mkOutOfStoreSymlink;
      inherit (lib.my) networkdAssignment systemdAwaitPostgres;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdHbZErWLmTPO/aEWB1Fup/aGMf31Un5Wk66FJwTz/8";
              files = {
                "object/minio.env" = {};
                "object/sharry.conf" = {
                  owner = "sharry";
                  group = "sharry";
                };
                "object/minio-client-config.json" = {
                  owner = config.my.user.config.name;
                  group = config.my.user.config.group;
                };
                "object/atticd.env" = {};
              };
            };

            firewall = {
              tcp.allowed = [ 9000 9001 config.services.sharry.config.bind.port 8069 ];
            };

            user.homeConfig = {
              home.file.".mc/config.json".source = mkOutOfStoreSymlink config.age.secrets."object/minio-client-config.json".path;
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
            services = {
              minio = {
                environment = {
                  MINIO_ROOT_USER = "minioadmin";
                  MINIO_DOMAIN = "s3.nul.ie";
                  MINIO_SERVER_URL = "https://s3.nul.ie";
                  MINIO_BROWSER_REDIRECT_URL = "https://minio.nul.ie";
                };
              };
              sharry = systemdAwaitPostgres pkgs.postgresql "colony-psql";
            };
          };

          environment = {
            systemPackages = with pkgs; [
              minio-client
            ];
          };

          services = {
            minio = {
              enable = true;
              region = "eu-central-1";
              browser = true;
              rootCredentialsFile = config.age.secrets."object/minio.env".path;
              dataDir = [ "/mnt/minio" ];
            };

            sharry = {
              enable = true;
              configOverridesFile = config.age.secrets."object/sharry.conf".path;

              config = {
                base-url = "https://share.${lib.my.c.pubDomain}";
                bind.address = "::";
                alias-member-enabled = true;
                webapp = {
                  chunk-size = "64M";
                };
                backend = {
                  auth = {
                    fixed = {
                      enabled = true;
                      user = "dev";
                    };
                    internal = {
                      enabled = true;
                      order = 50;
                    };
                  };
                  jdbc = {
                    url = "jdbc:postgresql://colony-psql:5432/sharry";
                    user = "sharry";
                  };
                  files = {
                    default-store = "minio";
                    stores = {
                      database.enabled = false;
                      minio = {
                        enabled = true;
                        type = "s3";
                        endpoint = "https://s3.nul.ie";
                        access-key = "share";
                        bucket = "share";
                      };
                    };
                  };
                  compute-checksum.parallel = 4;
                  signup.mode = "invite";
                  share = {
                    max-size = "128G";
                    max-validity = "3650 days";
                  };
                  mail = {
                    enabled = true;
                    smtp = {
                      host = "mail.nul.ie";
                      port = 587;
                      user = "sharry@nul.ie";
                      ssl-type = "starttls";
                      default-from = "Sharry <sharry@nul.ie>";
                      timeout = "30 seconds";
                    };
                  };
                };
              };
            };

            atticd = {
              enable = true;
              credentialsFile = config.age.secrets."object/atticd.env".path;
              settings = {
                listen = "[::]:8069";
                allowed-hosts = [ "nix-cache.${pubDomain}" ];
                api-endpoint = "https://nix-cache.${pubDomain}/";
                database = mkForce {}; # blank to pull from env
                storage = {
                  type = "s3";
                  region = "eu-central-1";
                  bucket = "nix-attic";
                  endpoint = "https://s3.nul.ie";
                };
                chunking = {
                  nar-size-threshold = 65536;
                  min-size = 16384;
                  avg-size = 65536;
                  max-size = 262144;
                };
              };
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 9000; guest.port = 9000; }
              { from = "host"; host.port = 9001; guest.port = 9001; }
              { from = "host"; guest.port = config.services.sharry.config.bind.port; }
            ];
          };
        })
      ];
    };
  };
}
