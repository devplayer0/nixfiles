{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain prefixes vips hiMTU;
in
{
  nixos.systems.hass = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      hi = {
        name = "hass-ctr";
        inherit domain;
        mtu = hiMTU;
        ipv4 = {
          address = net.cidr.host 103 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::5:3";
          address = net.cidr.host (65536*5+3) prefixes.hi.v6;
        };
      };
      lo = {
        name = "hass-ctr-lo";
        inherit domain;
        mtu = 1500;
        ipv4 = {
          address = net.cidr.host 103 prefixes.lo.v4;
          mask = 21;
          gateway = null;
        };
        ipv6 = {
          iid = "::5:3";
          address = net.cidr.host (65536*5+3) prefixes.lo.v6;
        };
      };
    };

    configuration = { lib, config, pkgs, assignments, allAssignments, ... }:
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
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGpYX2WbYwUqHp8bFFf0eHFrqrR8xp8IheguA054F8V4";
            files = { };
          };

          firewall = {
            tcp.allowed = [ ];
          };
        };

        environment = {
          systemPackages = with pkgs; [
            usbutils
          ];
        };

        systemd = {
          network.networks = {
            "80-container-host0" = networkdAssignment "host0" assignments.hi;
            "80-container-lan-lo" = networkdAssignment "lan-lo" assignments.lo;
          };
        };

        services = {
          home-assistant = {
            enable = true;
            config = {
              default_config = {};
              homeassistant = {
                name = "Home";
                unit_system = "metric";
                currency = "EUR";
                country = "IE";
                time_zone = "Europe/Dublin";
                external_url = "https://hass.${pubDomain}";
                internal_url = "http://hass-ctr.${domain}:${toString config.services.home-assistant.config.http.server_port}";
              };
              http = {
                use_x_forwarded_for = true;
                trusted_proxies = with allAssignments.middleman.internal; [
                  ipv4.address
                  ipv6.address
                ];
              };
            };
            extraComponents = [
              "default_config"
              "esphome"
              "google_translate"

              "met"
              "zha"
              "denonavr"
              "webostv"
            ];
            extraPackages = python3Packages: with python3Packages; [
              zlib-ng
              isal

              gtts
            ];
            configWritable = false;
            openFirewall = true;
          };
        };
      };
    };
  };
}
