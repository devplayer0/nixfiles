index: { lib, allAssignments, ... }:
let
  inherit (builtins) elemAt;
  inherit (lib.my) net mkVLAN;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain vlans prefixes vips routers routersPubV4;

  name = elemAt routers index;
  otherIndex = 1 - index;
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
        mtu = 1500;
        ipv4 = {
          address = net.cidr.host (index + 1) prefixes.core.v4;
          gateway = null;
        };
      };
      hi = {
        name = "${name}-hi";
        inherit domain;
        mtu = 9000;
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
        mtu = 1500;
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
        mtu = 1500;
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
        ipv6 = {
          address = net.cidr.host ((1*65536*65536*65536) + index + 1) prefixes.as211024.v6;
          gateway = net.cidr.host ((2*65536*65536*65536) + 1) prefixes.as211024.v6;
        };
      };
    };

    extraAssignments = {
      router-hi.hi = {
        name = "router-hi";
        inherit domain;
        ipv4 = {
          address = vips.hi.v4;
          mask = 22;
        };
        ipv6.address = vips.hi.v6;
      };
      router-lo.lo = {
        name = "router-lo";
        inherit domain;
        ipv4 = {
          address = vips.lo.v4;
          mask = 21;
        };
        ipv6.address = vips.lo.v6;
      };
      router-ut.untrusted = {
        name = "router-ut";
        inherit domain;
        ipv4.address = vips.untrusted.v4;
        ipv6.address = vips.untrusted.v6;
      };
    };

    configuration = { lib, pkgs, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
        inherit (lib.my.c) networkd;
      in
      {
        imports = map (m: import m index) [
          ./keepalived.nix
          ./dns.nix
          ./radvd.nix
          ./kea.nix
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
                  if [ $IFACE = "wan-ifb" ]; then
                    ${pkgs.iproute2}/bin/tc filter add dev wan parent ffff: matchall action mirred egress redirect dev $IFACE
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

            netdevs = mkMerge [
              {
                "25-wan-ifb".netdevConfig = {
                  Name = "wan-ifb";
                  Kind = "ifb";
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
            ];

            networks =
            let
              mkVLANConfig = name:
              let
                iface = "lan-${name}";
              in
              {
                "60-${iface}" = mkMerge [
                  (networkdAssignment iface assignments."${name}")
                  {
                    dns = [ "127.0.0.1" "::1" ];
                    domains = [ config.networking.domain ];
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
              };
            in
            mkMerge [
              {
                "50-wan-ifb" = {
                  matchConfig.Name = "wan-ifb";
                  networkConfig = networkd.noL3;
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
                "50-wan" = mkMerge [
                  (networkdAssignment "wan" assignments.modem)
                  {
                    matchConfig.Name = "wan";
                    DHCP = "ipv4";
                    dns = [ "127.0.0.1" "::1" ];
                    dhcpV4Config.UseDNS = false;

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
                  }
                ];

                "55-lan" = {
                  matchConfig.Name = "lan";
                  vlan = [ "lan-hi" "lan-lo" "lan-untrusted" "wan-tunnel" ];
                  macvlan = [ "lan-core" ];
                  networkConfig = networkd.noL3;
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
                    routes = map (r: { routeConfig = r; }) [
                      {
                        Destination = lib.my.c.colony.prefixes.all.v4;
                        Gateway = allAssignments.estuary.as211024.ipv4.address;
                      }

                      {
                        Destination = lib.my.c.tailscale.prefix.v4;
                        Gateway = allAssignments.britway.as211024.ipv4.address;
                      }
                      {
                        Destination = lib.my.c.tailscale.prefix.v6;
                        Gateway = allAssignments.britway.as211024.ipv6.address;
                      }
                    ];
                  }
                ];
              }

              (mkVLANConfig "hi")
              (mkVLANConfig "lo")
              (mkVLANConfig "untrusted")

              {
                "60-lan-hi" = {
                  routes = map (r: { routeConfig = r; }) [
                    {
                      Destination = elemAt routersPubV4 otherIndex;
                      Gateway = net.cidr.host (otherIndex + 1) prefixes.hi.v4;
                    }
                  ];
                };
              }
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
              };
              extraRules =
              let
                aa = allAssignments;
              in
              ''
                table inet filter {
                  chain input {
                    iifname base meta l4proto { udp, tcp } th dport domain accept
                    iifname lan-core meta l4proto vrrp accept
                  }

                  chain routing-tcp {
                    ip daddr {
                      ${aa.castle.hi.ipv4.address},
                      ${aa.cellar.hi.ipv4.address},
                      ${aa.palace.hi.ipv4.address}
                    } tcp dport ssh accept
                    ip6 daddr {
                      ${aa.castle.hi.ipv6.address},
                      ${aa.cellar.hi.ipv6.address},
                      ${aa.palace.hi.ipv6.address}
                    } tcp dport ssh accept

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
                    ${lib.my.c.as211024.nftTrust}
                    iifname lan-untrusted jump filter-untrusted
                    iifname { wan, as211024, lan-untrusted } oifname { lan-hi, lan-lo } jump filter-routing
                    oifname as211024 accept
                  }
                  chain output { }
                }
                table inet nat {
                  chain prerouting {
                    ip daddr ${elemAt routersPubV4 index} meta l4proto { udp, tcp } th dport domain redirect to :5353
                    ip6 daddr ${assignments.as211024.ipv6.address} meta l4proto { udp, tcp } th dport domain redirect to :5353
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
