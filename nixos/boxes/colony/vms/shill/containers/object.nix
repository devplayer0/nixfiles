{ lib, ... }: {
  nixos.systems.object = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "object-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}7";
        ipv6 = {
          iid = "::7";
          address = "${lib.my.colony.start.ctrs.v6}7";
        };
      };
    };

    configuration = { lib, config, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf;
      inherit (lib.my) networkdAssignment;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFdHbZErWLmTPO/aEWB1Fup/aGMf31Un5Wk66FJwTz/8";
              files."minio.env" = {};
            };

            firewall = {
              tcp.allowed = [ 9000 9001 ];
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
            };
          };

          services = {
            minio = {
              enable = true;
              region = "eu-central-1";
              browser = true;
              rootCredentialsFile = config.age.secrets."minio.env".path;
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
