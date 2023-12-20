{ lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.colony) domain prefixes;
in
{
  nixos.systems.waffletail = { config, ... }: {
    system = "x86_64-linux";
    nixpkgs = "mine";
    rendered = config.configuration.config.my.asContainer;

    assignments = {
      internal = {
        name = "waffletail-ctr";
        inherit domain;
        ipv4.address = net.cidr.host 9 prefixes.ctrs.v4;
        ipv6 = {
          iid = "::9";
          address = net.cidr.host 9 prefixes.ctrs.v6;
        };
      };
      tailscale = with lib.my.c.tailscale; {
        ipv4 = {
          address = net.cidr.host 5 prefix.v4;
          mask = 32;
          gateway = null;
        };
        ipv6 = {
          address = net.cidr.host 5 prefix.v6;
          mask = 128;
        };
      };
    };

    configuration = { lib, config, assignments, ... }:
    let
      inherit (lib) concatStringsSep mkMerge mkIf mkForce;
      inherit (lib.my) networkdAssignment;
    in
    {
      config = {
        my = {
          deploy.enable = false;
          server.enable = true;

          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZc88lcSQ9zzQzDITdE/T5ty++TxFQUAED7p9YfFBiR";
            files = {
              "tailscale-auth.key" = {};
            };
          };

          firewall = {
            trustedInterfaces = [ "tailscale0" ];
            extraRules = ''
              table inet filter {
                chain forward {
                  iifname host0 oifname tailscale0 ip saddr ${prefixes.all.v4} accept
                  iifname host0 oifname tailscale0 ip6 saddr ${prefixes.all.v6} accept
                }
              }
              table inet nat {
                chain postrouting {
                  iifname tailscale0 ip daddr != ${prefixes.all.v4} snat to ${assignments.internal.ipv4.address}
                  iifname tailscale0 ip6 daddr != ${prefixes.all.v6} snat ip6 to ${assignments.internal.ipv6.address}
                }
              }
            '';
          };
        };

        systemd = {
          network.networks."80-container-host0" = networkdAssignment "host0" assignments.internal;
        };

        services = {
          tailscale =
          let
            advRoutes = concatStringsSep "," (with prefixes.all; [ v4 v6 ]);
          in
          {
            enable = true;
            authKeyFile = config.age.secrets."tailscale-auth.key".path;
            port = 41641;
            openFirewall = true;
            interfaceName = "tailscale0";
            extraUpFlags = [
              "--operator=${config.my.user.config.name}"
              "--login-server=https://ts.nul.ie"
              "--netfilter-mode=off"
              "--advertise-exit-node"
              "--advertise-routes=${advRoutes}"
              "--accept-routes=false"
            ];
          };
        };
      };
    };
  };
}
