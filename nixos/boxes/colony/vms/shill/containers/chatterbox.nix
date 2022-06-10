{ lib, ... }: {
  nixos.systems.chatterbox = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "chatterbox-ctr";
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.ctrs.v4}5";
        ipv6 = {
          iid = "::5";
          address = "${lib.my.colony.start.ctrs.v6}5";
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
              #key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICkly/tnPmoX05lDjEpQOkllPqYA0PY92pOKqvx8Po02";
              files."synapse.yaml" = {};
            };

            firewall = {
              tcp.allowed = [ 8008 ];
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            #matrix-synapse = {
            #  enable = true;
            #  withJemalloc = true;
            #  settings = {

            #  };
            #};
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
