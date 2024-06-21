{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib) mkMerge mkIf;
  inherit (lib.my) networkdAssignment;
  inherit (lib.my.c.kelder) ipv4MTU;

  wg = {
    keyFile = "kelder/acquisition/airvpn-privkey";
    pskFile = "kelder/acquisition/airvpn-psk";
    fwMark = 42;
    routeTable = 51820;
  };

  # Forwarded in AirVPN config
  transmissionPeerPort = 26180;
in
{
  config = mkMerge [
    {
      my = {
        secrets = {
          files = {
            "${wg.keyFile}" = {
              group = "systemd-network";
              mode = "440";
            };
            "${wg.pskFile}" = {
              group = "systemd-network";
              mode = "440";
            };
          };
        };

        firewall = {
          extraRules = ''
            # Make sure that VPN connections are dropped (except for the Transmission port)
            table inet filter {
              chain tcp-ext {
                tcp dport ${toString transmissionPeerPort} accept
                iifname vpn return

                tcp dport { 9091, 9117, 7878, 8989, 8096 } accept
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
              # Specified by AirVPN
              MTUBytes = "1320";
            };
            wireguardConfig = {
              PrivateKeyFile = config.age.secrets."${keyFile}".path;
              FirewallMark = fwMark;
              RouteTable = routeTable;
            };
            wireguardPeers = [
              {
                # AirVPN IE
                wireguardPeerConfig = {
                  Endpoint = "146.70.94.2:1637";
                  PublicKey = "PyLCXAQT8KkM4T+dUsOQfn+Ub3pGxfGlxkIApuig+hk=";
                  PresharedKeyFile = config.age.secrets."${pskFile}".path;
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
                linkConfig.MTUBytes = toString ipv4MTU;
              }
            ];
            "90-vpn" = with wg; {
              matchConfig.Name = "vpn";
              address = [ "10.161.170.28/32" "fd7d:76ee:e68f:a993:b12d:6d15:c80a:9516/128" ];
              dns = [ "10.128.0.1" "fd7d:76ee:e68f:a993::1" ];
              routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
                {
                  Family = "both";
                  SuppressPrefixLength = 0;
                  Table = "main";
                  Priority = 100;
                }

                {
                  From = lib.my.c.kelder.prefixes.all.v4;
                  Table = "main";
                  Priority = 100;
                }
                {
                  To = lib.my.c.kelder.prefixes.all.v4;
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
