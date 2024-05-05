{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib) mkMerge mkIf;
  inherit (lib.my) networkdAssignment;
  inherit (lib.my.c.colony) prefixes;

  wg = {
    keyFile = "jackflix/airvpn-privkey";
    pskFile = "jackflix/airvpn-psk";
    fwMark = 42;
    routeTable = 51820;
  };

  # Forwarded in AirVPN config
  transmissionPeerPort = 47016;
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
          files."${wg.pskFile}" = {
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

                tcp dport { 19999, 9091, 9117, 7878, 8989, 8096, 2342 } accept
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
                # AirVPN NL
                wireguardPeerConfig = {
                  Endpoint = "2a00:1678:1337:2329:e5f:35d4:4404:ef9f:1637";
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
              }
            ];
            "90-vpn" = with wg; {
              matchConfig.Name = "vpn";
              address = [ "10.182.97.37/32" "fd7d:76ee:e68f:a993:735d:ef5e:6907:b122/128" ];
              dns = [ "10.128.0.1" "fd7d:76ee:e68f:a993::1" ];
              routingPolicyRules = map (r: { routingPolicyRuleConfig = r; }) [
                {
                  Family = "both";
                  SuppressPrefixLength = 0;
                  Table = "main";
                  Priority = 100;
                }

                {
                  From = prefixes.all.v4;
                  Table = "main";
                  Priority = 100;
                }
                {
                  To = prefixes.all.v4;
                  Table = "main";
                  Priority = 100;
                }

                {
                  From = prefixes.all.v6;
                  Table = "main";
                  Priority = 100;
                }
                {
                  To = prefixes.all.v6;
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
