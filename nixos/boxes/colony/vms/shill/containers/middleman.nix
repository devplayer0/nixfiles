{
  nixos.systems.middleman = {
    system = "x86_64-linux";
    nixpkgs = "mine";

    assignments = {
      internal = {
        name = "middleman-ctr";
        altNames = [ "http" ];
        ipv4.address = "10.100.2.2";
        ipv6 = rec {
          iid = "::2";
          address = "2a0e:97c0:4d0:bbb2${iid}";
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
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAuvP9DEsffop53Fsh7xIdeVyQSF6tSKrOUs2faq6rip";
            };

            firewall = {
              tcp.allowed = [ "http" "https" ];
            };

            tmproot.persistence.config.directories = [
            ];
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            nginx = {
              enable = true;
              enableReload = true;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [
              { from = "host"; host.port = 8080; guest.port = 80; }
              { from = "host"; host.port = 8443; guest.port = 443; }
            ];
          };
        })
      ];
    };
  };
}
