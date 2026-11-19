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

    configuration = { lib, pkgs, pkgsFlakes, config, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (config.my.user.homeConfig.lib.file) mkOutOfStoreSymlink;
      inherit (lib.my) networkdAssignment systemdAwaitPostgres;

      # TODO: Migrate the object store and remove this MinIO compatibility pin.
      minioPkgs = import pkgsFlakes.mine-stable {
        inherit (pkgs.stdenv.hostPlatform) system;
        config.permittedInsecurePackages = [ "minio-2025-10-15T17-29-55Z" ];
      };
      # Unstable reserves services.minio for its removed-option diagnostic.
      minioModule = import "${pkgsFlakes.mine-stable}/nixos/modules/services/web-servers/minio.nix" {
        inherit lib;
        pkgs = minioPkgs;
        config = config // { services = config.services // { minio = config.my.minio; }; };
      };
    in
    {
      options.my.minio = minioModule.options.services.minio;
      config = mkMerge [
        minioModule.config
        {
          fileSystems = {
            "/var/lib/harmonia" = {
              device = "/mnt/nix-cache";
              options = [ "bind" ];
              fsType = "none";
            };
          };

          my = {
            deploy.enable = false;
            server.enable = true;

            minio = {
              enable = true;
              region = "eu-central-1";
              browser = true;
              rootCredentialsFile = config.age.secrets."object/minio.env".path;
              dataDir = [ "/mnt/minio" ];
            };

            tmproot.persistence.config.directories = mkIf (config.my.tmproot.persistence.dir != null) [
              {
                directory = config.my.minio.configDir;
                user = "minio";
                group = "minio";
              }
            ];

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdHbZErWLmTPO/aEWB1Fup/aGMf31Un5Wk66FJwTz/8";
              files = {
                "object/minio.env" = {};
                "object/minio-client-config.json" = {
                  owner = config.my.user.config.name;
                  group = config.my.user.config.group;
                };
                "object/atticd.env" = {};
                "nix-cache.key" = {};
                "object/hedgedoc.env" = {};
                "object/wastebin.env" = {};
              };
            };

            firewall = {
              tcp.allowed = [
                9000 9001
                8069
                5000
                config.services.hedgedoc.settings.port
                8088
              ];
            };

            user.homeConfig = {
              home.file.".mc/config.json".source = mkOutOfStoreSymlink config.age.secrets."object/minio-client-config.json".path;
            };
          };

          users = with lib.my.c.ids; mkMerge [
            (let inherit (config.services.atticd) user group; in {
              users."${user}" = {
                isSystemUser = true;
                uid = uids.atticd;
                group = group;
              };
              groups."${user}".gid = gids.atticd;
            })
            {
              users = {
                harmonia = {
                isSystemUser = true;
                group = "harmonia";
                  shell = pkgs.bashInteractive;
                  openssh.authorizedKeys.keyFiles = [
                    lib.my.c.sshKeyFiles.harmonia
                    lib.my.c.sshKeyFiles.me
                  ];
                };
              };
              groups = {
                harmonia = { };
              };
            }
          ];

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;

            services =
            let
              awaitPostgres = systemdAwaitPostgres pkgs.postgresql "colony-psql";
            in
            {
              minio = {
                environment = {
                  MINIO_ROOT_USER = "minioadmin";
                  MINIO_DOMAIN = "s3.nul.ie";
                  MINIO_SERVER_URL = "https://s3.nul.ie";
                  MINIO_BROWSER_REDIRECT_URL = "https://minio.nul.ie";
                };
              };

              atticd = mkMerge [
                awaitPostgres
                {
                  serviceConfig = {
                    # Needs to be able to access its data
                    DynamicUser = mkForce false;
                    BindPaths = [ "/mnt/atticd:/var/lib/atticd/storage" ];
                  };
                }
              ];

              harmonia-dev = {
                # environment.RUST_LOG = mkForce "trace";
                # serviceConfig = {
                #   StateDirectory = "harmonia";
                #   DynamicUser = mkForce false;
                # };
              };
              harmonia-daemon = {
                # environment.RUST_LOG = mkForce "trace";
                preStart = ''
                  ${config.nix.package}/bin/nix store info --store /var/lib/harmonia
                '';
                serviceConfig = {
                  User = "harmonia";
                  Group = "harmonia";
                  StateDirectory = "harmonia";
                  DynamicUser = mkForce false;
                };
              };
            };
          };

          environment.systemPackages = [ minioPkgs.minio-client ];

          services = {
            # `slop build` on `palace` pushes into Harmonia's store
            slop-broker-cache = {
              enable = true;
              user = "harmonia";
              store = "/var/lib/harmonia";
              # As `ci/push-to-cache.sh` does; `harmonia-dev`'s runtime directory
              home = "/run/harmonia";
              brokerKeys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJMx9rrKaPGFnwdvdEKCHyonMjWi/kDWMkbZkSEHijhp slop-broker cache (palace)"
              ];
            };

            atticd = {
              enable = false;
              environmentFile = config.age.secrets."object/atticd.env".path;
              settings = {
                listen = "[::]:8069";
                allowed-hosts = [ "nix-cache.${pubDomain}" ];
                api-endpoint = "https://nix-cache.${pubDomain}/";
                database = mkForce {}; # blank to pull from env
                storage = {
                  type = "local";
                  path = "/var/lib/atticd/storage";
                };
                chunking = {
                  nar-size-threshold = 65536;
                  min-size = 16384;
                  avg-size = 65536;
                  max-size = 262144;
                };
              };
            };

            harmonia-dev = {
              daemon = {
                enable = true;
                storeDir = "/nix/store";
                dbPath = "/var/lib/harmonia/nix/var/nix/db/db.sqlite";
              };
              cache = {
                enable = true;
                signKeyPaths = [ config.age.secrets."nix-cache.key".path ];
                settings = {
                  priority = 30;
                  virtual_nix_store = "/nix/store";
                  real_nix_store = "/var/lib/harmonia/nix/store";
                };
              };
            };

            hedgedoc = {
              enable = true;
              environmentFile = config.age.secrets."object/hedgedoc.env".path;
              settings = {
                domain = "md.${pubDomain}";
                protocolUseSSL = true;
                db = {
                  dialect = "postgresql";
                  username = "hedgedoc";
                  database = "hedgedoc";
                  host = "colony-psql";
                };
                host = "::";
                allowAnonymous = false;
                allowAnonymousEdits = true;
                email = true;
                allowEmailRegister = false;
              };
            };

            wastebin = {
              enable = true;
              settings = {
                WASTEBIN_MAX_BODY_SIZE = 67108864; # 16 MiB
                WASTEBIN_PASSWORD_SALT = "TeGhaemeer0Siez3";
              };
              secretFile = config.age.secrets."object/wastebin.env".path;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 9000; guest.port = 9000; }
              { from = "host"; host.port = 9001; guest.port = 9001; }
            ];
          };
        })
      ];
    };
  };
}
