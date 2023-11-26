index: { lib, allAssignments, ... }:
let
  inherit (builtins) elemAt;
  inherit (lib.my) net;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain vlans prefixes routers;

  name = elemAt routers index;
in
{
  nixos.systems."${name}" = {
    assignments = {
      modem = {
        ipv4 = {
          address = net.cidr.host (254 - index) prefixes.modem.v4;
          gateway = null;
        };
      };
      core = {
        name = "${name}-core";
        inherit domain;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.core.v4;
          gateway = null;
        };
      };
      hi = {
        inherit domain;
        name = "${name}-hi";
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
      as211024 = {
        ipv4 = {
          address = net.cidr.host (index + 2) prefixes.as211024.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host ((1*65536*65536*65536) + index + 1) prefixes.as211024.v6;
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = map (m: import m index) [
          ./mstpd.nix
          ./keepalived.nix
          ./dns.nix
        ];

        config = {
          environment = {
            systemPackages = with pkgs; [
              ethtool
              conntrack-tools
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

            networkd-dispatcher = {
              enable = true;
              rules = {
                # tc filter hasn't been networkd-ified yet
                setup-wan-mirror = {
                  onState = [ "configured" ];
                  script = ''
                  #!${pkgs.runtimeShell}
                  if [ $IFACE = "wan-phy-ifb" ]; then
                    ${pkgs.iproute2}/bin/tc filter add dev wan-phy parent ffff: matchall action mirred egress redirect dev $IFACE
                  fi
                  '';
                };
              };
            };
          };

          networking.domain = "h.${pubDomain}";

          systemd.services = {
            ipsec =
            let
              waitOnline = "systemd-networkd-wait-online@wan.service";
            in
            {
              after = [ waitOnline ];
              requires = [ waitOnline ];
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
                "25-wan-phy-ifb".netdevConfig = {
                  Name = "wan-phy-ifb";
                  Kind = "ifb";
                };
                "25-wan".netdevConfig = {
                  Name = "wan";
                  Kind = "bridge";
                };
                "25-lan" = {
                  netdevConfig = {
                    Name = "lan";
                    Kind = "bridge";
                  };
                  extraConfig = ''
                    [Bridge]
                    STP=true
                  '';
                };
                "30-lan-core".netdevConfig = {
                  Name = "lan-core";
                  Kind = "macvlan";
                  MTUBytes = "1500";
                };
              }

              (mkVLAN "lan-hi" vlans.hi)
              (mkVLAN "lan-lo" vlans.lo)
              (mkVLAN "lan-untrusted" vlans.untrusted)
              (mkVLAN "wan-tunnel" vlans.wan)
            ];

            networks =
            let
              mkVLANConfig = name: mtu:
              let
                iface = "lan-${name}";
              in
              {
                "60-${iface}" = mkMerge [
                  (networkdAssignment iface assignments."${name}")
                  {
                    linkConfig.MTUBytes = toString mtu;
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
                  qdiscConfig = {
                    Parent = "ingress";
                    Handle = "0xffff";
                  };
                  extraConfig = ''
                    [CAKE]
                    Parent=root
                    Bandwidth=24M
                    RTTSec=1ms
                  '';
                };
                "50-wan-phy-ifb" = {
                  matchConfig.Name = "wan-phy-ifb";
                  networkConfig = {
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = false;
                    LLDP = false;
                    EmitLLDP = false;
                  };
                  extraConfig = ''
                    [CAKE]
                    Bandwidth=235M
                    RTTSec=10ms
                    PriorityQueueingPreset=besteffort
                    # DOCSIS preset
                    OverheadBytes=18
                    MPUBytes=64
                    CompensationMode=none
                  '';
                };

                "50-wan-tunnel" = {
                  matchConfig.Name = "wan-tunnel";
                  networkConfig.Bridge = "wan";
                  linkConfig.MTUBytes = "1500";
                };
                "50-wan" = mkMerge [
                  (networkdAssignment "wan" assignments.modem)
                  {
                    matchConfig.Name = "wan";
                    DHCP = "ipv4";
                    dns = [ "127.0.0.1" "::1" ];
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
                  vlan = [ "lan-hi" "lan-lo" "lan-untrusted" "wan-tunnel" ];
                  macvlan = [ "lan-core" ];
                  networkConfig = {
                    LinkLocalAddressing = "no";
                    IPv6AcceptRA = false;
                    LLDP = false;
                    EmitLLDP = false;
                  };
                };
                "60-lan-core" = mkMerge [
                  (networkdAssignment "lan-core" assignments.core)
                  {
                    matchConfig.Name = "lan-core";
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];

                "90-l2mesh-as211024" = mkMerge [
                  (networkdAssignment "as211024" assignments.as211024)
                  {
                    matchConfig.Name = "as211024";
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
              }

              (mkVLANConfig "hi" 9000)
              (mkVLANConfig "lo" 1500)
              (mkVLANConfig "untrusted" 1500)
            ];
          };

          my = {
            secrets = {
              files = {
                "l2mesh/as211024.key" = {};
              };
            };

            vpns = {
              l2.pskFiles = {
                as211024 = config.age.secrets."l2mesh/as211024.key".path;
              };
            };
            firewall = {
              trustedInterfaces = [ "lan-hi" "lan-lo" ];
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
                    iifname lan-untrusted jump filter-untrusted
                    iifname { wan, lan-untrusted } oifname { lan-hi, lan-lo } jump filter-routing
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
