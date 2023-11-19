{ index, name }: { lib, ... }:
let
  inherit (lib.my) net;
  inherit (lib.my.c.home) domain vlans prefixes;
in
{
  nixos.systems."${name}" = {
    assignments = {
      modem = {
        ipv4.address = net.cidr.host (254 - index) prefixes.modem.v4;
      };
      core = {
        name = "${name}-core";
        inherit domain;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.core.v4;
          mask = 24;
        };
      };
      hi = {
        inherit domain;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.hi.v4;
          mask = 22;
          gateway = null;
        };
        ipv6.address = net.cidr.host (index + 1) prefixes.hi.v6;
      };
      lo = {
        name = "${name}-lo";
        inherit domain;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.lo.v4;
          mask = 21;
          gateway = null;
        };
        ipv6.address = net.cidr.host (index + 1) prefixes.lo.v6;
      };
      untrusted  = {
        name = "${name}-ut";
        inherit domain;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.untrusted.v4;
          mask = 24;
          gateway = null;
        };
        ipv6.address = net.cidr.host (index + 1) prefixes.untrusted.v6;
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ (import ./dns.nix index) ];

        config = {
          environment = {
            systemPackages = with pkgs; [
              ethtool
            ];
          };

          services = {
            resolved = {
              llmnr = "false";
              extraConfig = ''
                MulticastDNS=false
              '';
            };

            iperf3 = {
              enable = true;
              openFirewall = true;
            };
          };

          systemd.network = {
            wait-online.enable = false;
            config = {
              networkConfig = {
                ManageForeignRoutes = false;
              };
            };

            netdevs =
            let
              mkVLAN = name: vid: {
                "25-${name}" = {
                  netdevConfig = {
                    Name = name;
                    Kind = "vlan";
                  };
                  vlanConfig.Id = vid;
                };
              };
            in
            mkMerge [
              {
                "25-wan".netdevConfig = {
                  Name = "wan";
                  Kind = "bridge";
                };
                "25-lan".netdevConfig = {
                  Name = "lan";
                  Kind = "bridge";
                };
              }

              (mkVLAN "hi" vlans.hi)
              (mkVLAN "lo" vlans.lo)
              (mkVLAN "untrusted" vlans.untrusted)
              (mkVLAN "wan-tunnel" vlans.wan)
            ];

            links = {
              "10-lan-jim" = {
                matchConfig = {
                  # Matching against MAC address seems to break VLAN interfaces
                  # (since they share the same MAC address)
                  Driver = "igb";
                  Path = "pci-0000:01:00.0";
                };
                linkConfig = {
                  Name = "lan-jim";
                  RxBufferSize = 4096;
                  TxBufferSize = 4096;
                  MTUBytes = toString lib.my.c.home.hiMTU;
                };
              };
            };

            networks =
            let
              mkVLANConfig = name: {
                "60-${name}" = mkMerge [
                  (networkdAssignment name assignments.hi)
                  {
                    dns = [ "127.0.0.1" "::1" ];
                    domains = [ config.networking.domain ];
                    networkConfig = {
                      IPv6AcceptRA = mkForce false;
                      # IPv6SendRA = true;
                    };
                    ipv6SendRAConfig = {
                      DNS = [
                        (net.cidr.host 1 prefixes."${name}".v4)
                        (net.cidr.host 2 prefixes."${name}".v4)
                        (net.cidr.host 1 prefixes."${name}".v6)
                        (net.cidr.host 2 prefixes."${name}".v6)
                      ];
                      Domains = [ config.networking.domain ];
                    };
                    ipv6Prefixes = [
                      {
                        ipv6PrefixConfig.Prefix = prefixes."${name}".v6;
                      }
                    ];
                  }
                ];
              };
            in
            mkMerge [
              {
                "50-wan-phy" = {
                  matchConfig.Name = "wan-phy";
                  networkConfig.Bridge = "wan";
                };
                "50-wan-tunnel" = {
                  matchConfig.Name = "wan-tunnel";
                  networkConfig.Bridge = "wan";
                };
                "50-wan" = mkMerge [
                  (networkdAssignment "wan" assignments.modem)
                  {
                    matchConfig.Name = "wan";
                    DHCP = "ipv4";
                    dhcpV4Config.UseDNS = false;
                    routes = map (r: { routeConfig = r; }) [
                      # {
                      #   Destination = prefixes.ctrs.v4;
                      #   Gateway = allAssignments.shill.routing.ipv4.address;
                      # }
                    ];
                  }
                ];

                "50-lan-jim" = {
                  matchConfig.Name = "lan-jim";
                  networkConfig.Bridge = "lan";
                };
                "50-lan-dave" = {
                  matchConfig.Name = "lan-dave";
                  networkConfig.Bridge = "lan";
                };
                "55-lan" = {
                  matchConfig.Name = "lan";
                  vlan = [ "hi" "lo" "untrusted" ];
                };
              }

              (mkVLANConfig "hi")
              (mkVLANConfig "lo")
              (mkVLANConfig "untrusted")
            ];
          };

          my = {
            secrets = {
              files = {
                # "estuary/kelder-wg.key" = {
                #   owner = "systemd-network";
                # };
              };
            };

            firewall = {
              trustedInterfaces = [ "hi" "lo" ];
              udp.allowed = [ 5353 ];
              tcp.allowed = [ 5353 ];
              nat = {
                enable = true;
                externalInterface = "wan";
                # externalIP = assignments.internal.ipv4.address;
                forwardPorts = [
                  # {
                  #   port = "http";
                  #   dst = allAssignments.middleman.internal.ipv4.address;
                  # }
                ];
              };
              extraRules =
              let
                aa = allAssignments;
                matchInet = rule: sys: ''
                  ip daddr ${aa."${sys}".hi.ipv4.address} ${rule}
                  ip6 daddr ${aa."${sys}".hi.ipv6.address} ${rule}
                '';
              in
              ''
                table inet filter {
                  chain input {
                    iifname base meta l4proto { udp, tcp } th dport domain accept
                  }

                  chain routing-tcp {
                    # Safe enough to allow all SSH
                    tcp dport ssh accept

                    return
                  }
                  chain routing-udp {
                    return
                  }
                  chain filter-routing {
                    tcp flags & (fin|syn|rst|ack) == syn ct state new jump routing-tcp
                    meta l4proto udp ct state new jump routing-udp
                    return
                  }
                  chain filter-untrusted {
                    ip daddr ${prefixes.modem.v4} reject
                    oifname wan accept
                    return
                  }

                  chain forward {
                    iifname untrusted jump filter-untrusted
                    iifname { wan, untrusted } oifname { hi, lo } jump filter-routing
                  }
                  chain output { }
                }
                table inet nat {
                  chain prerouting {
                    ${matchInet "meta l4proto { udp, tcp } th dport domain redirect to :5353" name}
                  }
                  chain postrouting {
                    oifname wan masquerade
                  }
                }
              '';
            };
          };
        };
      };
  };
}
