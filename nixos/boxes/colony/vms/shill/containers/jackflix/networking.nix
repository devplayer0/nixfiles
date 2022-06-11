{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib) mkMerge;
  inherit (lib.my) networkdAssignment;

  wg = {
    keyFile = "jackflix-wg-privkey.txt";
    fwMark = 42;
    routeTable = 51820;
  };
in
{
  config = {
    my = {
      secrets = {
        files."${wg.keyFile}" = {
          group = "systemd-network";
          mode = "440";
        };
      };

      firewall = {
        tcp.allowed = [ ];
      };
    };

    environment.systemPackages = with pkgs; [
      wireguard-tools
    ];

    systemd = {
      network = {
        netdevs."30-vpn" = with wg; {
          netdevConfig = {
            Name = "vpn";
            Kind = "wireguard";
          };
          wireguardConfig = {
            PrivateKeyFile = config.age.secrets."${keyFile}".path;
            FirewallMark = fwMark;
            RouteTable = routeTable;
          };
          wireguardPeers = [
            {
              # mlvd-de32
              wireguardPeerConfig = {
                Endpoint = "146.70.107.194:51820";
                PublicKey = "uKTC5oP/zfn6SSjayiXDDR9L82X0tGYJd5LVn5kzyCc=";
                AllowedIPs = [ "0.0.0.0/0" "::/0" ];
              };
            }
          ];
        };

        networks = {
          "80-container-host0" = mkMerge [
            (networkdAssignment "host0" assignments.internal)
            {
              networkConfig.DNSDefaultRoute = false;
            }
          ];
          "90-vpn" = with wg; {
            matchConfig.Name = "vpn";
            address = [ "10.68.19.11/32" "fc00:bbbb:bbbb:bb01::5:130a/128" ];
            dns = [ "10.64.0.1" ];
            routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
              {
                Family = "both";
                SuppressPrefixLength = 0;
                Table = "main";
                Priority = 100;
              }

              {
                From = lib.my.colony.prefixes.all.v4;
                Table = "main";
                Priority = 100;
              }
              {
                To = lib.my.colony.prefixes.all.v4;
                Table = "main";
                Priority = 100;
              }

              {
                From = lib.my.colony.prefixes.all.v6;
                Table = "main";
                Priority = 100;
              }
              {
                To = lib.my.colony.prefixes.all.v6;
                Table = "main";
                Priority = 100;
              }

              {
                Family = "both";
                InvertRule = true;
                FirewallMark = fwMark;
                Table = routeTable;
                Priority = 110;
              }
            ];
          };
        };
      };
    };
  };
}
