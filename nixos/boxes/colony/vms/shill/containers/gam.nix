{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.gam = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "gam-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 11 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::11";
          address = net.cidr.host 11 prefixes.ctrs.v6;
        };
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;
    in
    {
      config = mkMerge [
        {
          my = {
            deploy.enable = false;
            server.enable = true;

            secrets = {
              key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAvDlH3nT1kve741gBluYmn5KQs8yz7FAEt8qLt+f0K6";
              files = {
                "gam/terraria.conf" = {
                  owner = "terraria";
                  group = "terraria";
                };
              };
            };
          };

          systemd = {
            network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
          };

          services = {
            terraria = {
              enable = true;
              noUPnP = true;
              messageOfTheDay = "sup gamers";
              autoCreatedWorldSize = "large";
              worldPath = "/var/lib/terraria/NotWorld.wld";
              configFile = config.age.secrets."gam/terraria.conf".path;
              openFirewall = true;
            };
          };
        }
        (mkIf config.my.build.isDevVM {
          virtualisation = {
            forwardPorts = [ ];
          };
        })
      ];
    };
  };
}
