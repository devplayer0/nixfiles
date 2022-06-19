{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib) mkMerge mkIf;
  inherit (lib.my) networkdAssignment;

  wg = {
    keyFile = "jackflix/mullvad-privkey";
    fwMark = 42;
    routeTable = 51820;
  };

  # Forwarded in Mullvad config
  transmissionPeerPort = 55471;
in
{
  config = mkMerge [
    {
      my = {
        secrets = {
          files."${wg.keyFile}" = {
            group = "systemd-network";
            mode = "440";
          };
        };

        firewall = {
          extraRules = ''
            # Make sure that VPN connections are dropped (except for the Transmission port)
            table inet filter {
              chain tcp-ext {
                tcp dport ${toString transmissionPeerPort} accept
                iifname vpn return

                tcp dport { 19999, 9091, 9117, 7878, 8989, 8096 } accept
                return
              }
              chain input {
                tcp flags & (fin|syn|rst|ack) == syn ct state new jump tcp-ext
              }
            }
          '';
        };
      };

      environment.systemPackages = with pkgs; [
        wireguard-tools
      ];

      services = {
        transmission.settings.peer-port = transmissionPeerPort;
      };

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
    }
    (mkIf config.my.build.isDevVM {
      virtualisation = {
        forwardPorts = [
          # Transmission
          { from = "host"; host.port = 9091; guest.port = 9091; }
          # Jackett
          { from = "host"; host.port = 9117; guest.port = 9117; }
          # Radarr
          { from = "host"; host.port = 7878; guest.port = 7878; }
          # Sonarr
          { from = "host"; host.port = 8989; guest.port = 8989; }
          # Jellyfin
          { from = "host"; host.port = 8096; guest.port = 8096; }
        ];
      };
    })
  ];
}
