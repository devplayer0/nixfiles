{ lib, ... }: {
  nixos.systems.colony-psql = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "colony-psql-ctr";
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
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICkly/tnPmoX05lDjEpQOkllPqYA0PY92pOKqvx8Po02";
            };

            firewall = {
              tcp.allowed = [ 5432 ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            postgresql = {
              package = pkgs.postgresql_14;
              enable = true;
              enableTCPIP = true;
              ensureUsers = [
                {
                  name = "root";
                  ensurePermissions = {
                    "ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
                  };
                }
              ];
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
