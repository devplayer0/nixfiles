{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain prefixes vips vlanDns hiMTU;
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
      core = {
        inherit domain;
        name = "unifi-ctr-core";
        mtu = 1500;
        ipv4 = {
          address = net.cidr.host 21 prefixes.core.v4;
          gateway = null;
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
          network.networks = {
            "80-container-host0" = mkMerge [
              (networkdAssignment "host0" assignments.hi)
              { networkConfig = vlanDns "hi"; }
            ];
            "80-lan-core" = networkdAssignment "lan-core" assignments.core;
          };
        };

        services = {
          unifi = {
            enable = true;
            openFirewall = true;
            unifiPackage = pkgs.unifi;
            mongodbPackage = pkgs.mongodb-7_0;
          };
        };
      };
    };
  };
}
