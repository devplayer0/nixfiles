{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips hiMTU;
in
{
  nixos.systems.unifi = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      hi = {
        name = "unifi-ctr";
        inherit domain;
        mtu = hiMTU;
        ipv4 = {
          address = net.cidr.host 100 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::5:1";
          address = net.cidr.host (65536*5+1) prefixes.hi.v6;
        };
      };
    };

    configuration = { lib, config, pkgs, assignments, ... }:
    let
      inherit (lib) mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;
    in
    {
      config = {
        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKdgcziQki/RH7E+NH2bYnzSVKaJ27905Yo5TcOjSh/U";
            files = { };
          };

          firewall = {
            tcp.allowed = [ 8443 ];
          };
        };

        systemd = {
          network.networks."80-container-host0" = networkdAssignment "host0" assignments.hi;
        };

        services = {
          unifi = {
            enable = true;
            openFirewall = true;
            unifiPackage = pkgs.unifi8;
            mongodbPackage = pkgs.mongodb-6_0;
          };
        };
      };
    };
  };
}
