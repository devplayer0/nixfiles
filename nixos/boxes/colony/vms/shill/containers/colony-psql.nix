{ lib, ... }: {
  nixos.systems.colony-psql = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "colony-psql-ctr";
        altNames = [ "colony-psql" ];
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}4";
        ipv6 = {
          iid = "::4";
          address = "${lib.my.colony.start.ctrs.v6}4";
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, ... }:
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
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINjxrgtTqLfKzmg14ZajkgViNXaM4cuTMvuJqETvj4Iv";
            };

            firewall = {
              tcp.allowed = [ 19999 5432 ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            netdata = {
              enable = true;
              python = {
                enable = true;
                extraPackages = ps: with ps; [ psycopg2 ];
              };
              configDir = {
                "python.d/postgres.conf" = pkgs.writeText "netdata-postgres.conf" ''
                  local:
                    user: postgres
                '';
              };
            };

            postgresql = {
              package = pkgs.postgresql_14;
              enable = true;
              enableTCPIP = true;

              authentication = with lib.my.colony.prefixes; ''
                local all postgres peer map=local

                host all all ${all.v4} md5
                host all all ${all.v6} md5
              '';
              identMap = ''
                local postgres postgres
                local root     postgres
                local netdata  postgres
                local dev      postgres
              '';
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 55432; guest.port = 5432; }
            ];
          };
        })
      ];
    };
  };
}
