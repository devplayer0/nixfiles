{ lib, ... }:
let
  inherit (builtins) elemAt;
  inherit (lib.my) net mkVLAN;
  inherit (lib.my.c.colony) pubV4 domain prefixes;
in
{
  nixos = {
    vpns = {
      l2 = {
        as211024 = {
          vni = 211024;
          security.enable = true;
          peers = {
            estuary.addr = pubV4;
            # river.addr = elemAt lib.my.c.home.routersPubV4 0;
            stream.addr = elemAt lib.my.c.home.routersPubV4 1;
          };
        };
      };
    };
  };
  nixos.systems.estuary = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments = {
      internal = {
        name = "estuary-vm";
        altNames = [ "fw" ];
        inherit domain;
        ipv4 = {
          address = pubV4;
          mask = 24;
          gateway = "94.142.240.254";
          genPTR = false;
        };
        ipv6 = {
          address = "2a02:898:0:20::329:1";
          mask = 64;
          gateway = "2a02:898:0:20::1";
          genPTR = false;
        };
      };
      base = {
        name = "estuary-vm-base";
        inherit domain;
        ipv4 = {
          address = net.cidr.host 1 prefixes.base.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.base.v6;
      };
      as211024 = {
        ipv4 = {
          address = net.cidr.host 1 prefixes.as211024.v4;
          gateway = null;
        };
        ipv6.address = net.cidr.host 1 prefixes.as211024.v6;
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) flatten mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ./dns.nix ./bgp.nix ];

        config = mkMerge [
          {
            boot.kernelParams = [ "console=ttyS0,115200n8" ];
            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-label/ESP";
                fsType = "vfat";
              };
              "/nix" = {
                device = "/dev/disk/by-label/nix";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/disk/by-label/persist";
                fsType = "ext4";
                neededForBoot = true;
              };
            };

            environment = {
              systemPackages = with pkgs; [
                ethtool
                conntrack-tools
                wireguard-tools
              ];
            };

            services = {
              fstrim = lib.my.c.colony.fstrimConfig;
              lvm = {
                dmeventd.enable = true;
              };
              resolved = {
                llmnr = "false";
                extraConfig = ''
                  MulticastDNS=false
                '';
              };
              netdata.enable = true;

              iperf3 = {
                enable = true;
                openFirewall = true;
              };
            };

            systemd = {
              services =
              let
                waitOnline = "systemd-networkd-wait-online@wan.service";
              in
              {
                bird2 = {
                  after = [ waitOnline ];
                  # requires = [ waitOnline ];
                };
                ipsec = {
                  after = [ waitOnline ];
                  requires = [ waitOnline ];
                };
              };
            };

            #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
            systemd.network = {
              wait-online.enable = false;
              config = {
                networkConfig = {
                  ManageForeignRoutes = false;
                };
              };

              netdevs = mkMerge [
                (mkVLAN "ifog" 409)

                (mkVLAN "frys-ix" 701)
                (mkVLAN "nl-ix" 1845)
                (mkVLAN "fogixp" 1147)
                (mkVLAN "ifog-transit" 702)

                {
                  "30-kelder" = {
                    netdevConfig = {
                      Name = "kelder";
                      Kind = "wireguard";
                    };
                    wireguardConfig = {
                      PrivateKeyFile = config.age.secrets."estuary/kelder-wg.key".path;
                      ListenPort = lib.my.c.kelder.vpn.port;
                    };
                    wireguardPeers = [
                      {
                        wireguardPeerConfig = {
                          PublicKey = "7N9YdQaCMWWIwAnW37vrthm9ZpbnG4Lx3gheHeRYz2E=";
                          AllowedIPs = [ allAssignments.kelder.estuary.ipv4.address ];
                          PersistentKeepalive = 25;
                        };
                      }
                    ];
                  };
                }
              ];

              links = {
                "10-wan" = {
                  matchConfig = {
                    Driver = "igb";
                    Path = "pci-0000:01:00.0";
                    # Matching against MAC address seems to break VLAN interfaces (since they share the same MAC address)
                    #MACAddress = "d0:50:99:fa:a7:99";
                  };
                  linkConfig = {
                    Name = "wan";
                    RxBufferSize = 4096;
                    TxBufferSize = 4096;
                    MTUBytes = "9000";
                  };
                };
                # Mellanox ConnectX-2
                #"10-wan" = {
                #  matchConfig.MACAddress = "00:02:c9:56:24:6e";
                #  linkConfig.Name = "wan";
                #};

                "10-base" = {
                  matchConfig.MACAddress = "52:54:00:15:1a:53";
                  linkConfig.Name = "base";
                };
              };

              networks =
              let
                mkIXPConfig = name: ipv4: ipv6: {
                  "85-${name}" = {
                    matchConfig.Name = name;
                    address = [ ipv4 ipv6 ];
                    linkConfig.MTUBytes = "1500";
                    networkConfig = {
                      DHCP = "no";
                      LLDP = false;
                      EmitLLDP = false;
                      IPv6AcceptRA = false;
                    };
                  };
                };
              in
              mkMerge
              [
                (mkIXPConfig "frys-ix" "185.1.203.196/24" "2001:7f8:10f::3:3850:196/64")
                (mkIXPConfig "nl-ix" "193.239.116.145/22" "2001:7f8:13::a521:1024:1/64")
                (mkIXPConfig "fogixp" "185.1.147.159/24" "2001:7f8:ca:1::159/64")
              {
                "80-wan" = {
                  matchConfig.Name = "wan";
                  vlan = [ "ifog" ];
                  DHCP = "no";
                  address = with assignments.internal; [
                    (with ipv4; "${address}/${toString mask}")
                    (with ipv6; "${address}/${toString mask}")
                  ];
                  gateway = with assignments.internal; [
                    ipv4.gateway
                    ipv6.gateway
                  ];
                  networkConfig = {
                    # We're using an explicit gateway and Linux uses link local address for neighbour discovery, so we
                    # get lost to the router... (this was true in 23M Frankfurt)
                    #LinkLocalAddressing = "no";
                    IPv6AcceptRA = false;
                  };
                };
                "85-ifog" = {
                  matchConfig = {
                    Name = "ifog";
                    Kind = "vlan";
                  };
                  vlan = [ "frys-ix" "nl-ix" "fogixp" "ifog-transit" ];
                  networkConfig = {
                    LinkLocalAddressing = "no";
                    DHCP = "no";
                    LLDP = false;
                    EmitLLDP = false;
                    IPv6AcceptRA = false;
                  };
                };
                "85-ifog-transit" = {
                  matchConfig.Name = "ifog-transit";
                  address = [ "2a0c:9a40:100f:370::2/64" ];
                  linkConfig.MTUBytes = "1500";
                  networkConfig = {
                    DHCP = "no";
                    LLDP = false;
                    EmitLLDP = false;
                    IPv6AcceptRA = false;
                  };
                };

                "80-base" = mkMerge [
                  (networkdAssignment "base" assignments.base)
                  {
                    dns = [ "127.0.0.1" "::1" ];
                    domains = [ config.networking.domain ];
                    networkConfig = {
                      IPv6AcceptRA = mkForce false;
                      IPv6SendRA = true;
                    };
                    ipv6SendRAConfig = {
                      DNS = [ assignments.base.ipv6.address ];
                      Domains = [ config.networking.domain ];
                    };
                    ipv6Prefixes = [
                      {
                        ipv6PrefixConfig.Prefix = prefixes.base.v6;
                      }
                    ];
                    routes = map (r: { routeConfig = r; }) (flatten
                      ([
                        {
                          Destination = prefixes.vip1;
                          Gateway = allAssignments.colony.routing.ipv4.address;
                        }
                        {
                          Destination = prefixes.darts.v4;
                          Gateway = allAssignments.colony.routing.ipv4.address;
                        }
                        {
                          Destination = prefixes.cust.v6;
                          Gateway = allAssignments.colony.internal.ipv6.address;
                        }
                      ] ++
                      (map (pName: [
                        {
                          Gateway = allAssignments.colony.routing.ipv4.address;
                          Destination = prefixes."${pName}".v4;
                        }
                        {
                          Destination = prefixes."${pName}".v6;
                          Gateway = allAssignments.colony.internal.ipv6.address;
                        }
                      ]) [ "vms" "ctrs" "oci" ])));
                  }
                ];

                "90-l2mesh-as211024" = mkMerge [
                  (networkdAssignment "as211024" assignments.as211024)
                  {
                    matchConfig.Name = "as211024";
                    networkConfig.IPv6AcceptRA = mkForce false;
                  }
                ];
                "95-kelder" = {
                  matchConfig.Name = "kelder";
                  routes = [
                    {
                      routeConfig = {
                        Destination = allAssignments.kelder.estuary.ipv4.address;
                        Scope = "link";
                      };
                    }
                  ];
                };
              } ];
            };

            my = {
              secrets = {
                key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF9up7pXu6M/OWCKufTOfSiGcxMUk4VqUe7fLuatNFFA";
                files = {
                  "estuary/kelder-wg.key" = {
                    owner = "systemd-network";
                  };
                  "l2mesh/as211024.key" = {};
                };
              };
              server.enable = true;

              vpns = {
                l2.pskFiles = {
                  as211024 = config.age.secrets."l2mesh/as211024.key".path;
                };
              };
              firewall = {
                trustedInterfaces = [ "as211024" ];
                udp.allowed = [ 5353 lib.my.c.kelder.vpn.port ];
                tcp.allowed = [ 5353 "bgp" ];
                nat = {
                  enable = true;
                  externalInterface = "wan";
                  externalIP = assignments.internal.ipv4.address;
                  forwardPorts = [
                    {
                      port = "http";
                      dst = allAssignments.middleman.internal.ipv4.address;
                    }
                    {
                      port = "https";
                      dst = allAssignments.middleman.internal.ipv4.address;
                    }
                    {
                      port = 8448;
                      dst = allAssignments.middleman.internal.ipv4.address;
                    }

                    {
                      port = 2456;
                      dst = allAssignments.valheim-oci.internal.ipv4.address;
                      proto = "udp";
                    }
                    {
                      port = 2457;
                      dst = allAssignments.valheim-oci.internal.ipv4.address;
                      proto = "udp";
                    }
                  ];
                };
                extraRules =
                let
                  aa = allAssignments;
                  matchInet = rule: sys: ''
                    ip daddr ${aa."${sys}".internal.ipv4.address} ${rule}
                    ip6 daddr ${aa."${sys}".internal.ipv6.address} ${rule}
                  '';
                in
                ''
                  define ixps = { frys-ix, nl-ix, fogixp, ifog-transit }

                  table inet filter {
                    chain input {
                      iifname base meta l4proto { udp, tcp } th dport domain accept
                    }

                    chain routing-tcp {
                      # Safe enough to allow all SSH
                      tcp dport ssh accept

                      ${matchInet "tcp dport { http, https, 8448 } accept" "middleman"}
                      ${matchInet "udp dport { 2456-2457 } accept" "valheim-oci"}

                      return
                    }
                    chain routing-udp {
                      return
                    }
                    chain filter-routing {
                      ip daddr { ${prefixes.mail.v4}, ${prefixes.darts.v4} } accept
                      ip6 daddr ${prefixes.cust.v6} accept

                      tcp flags & (fin|syn|rst|ack) == syn ct state new jump routing-tcp
                      meta l4proto udp ct state new jump routing-udp
                      return
                    }
                    chain ixp {
                      ether type != { ip, ip6, arp, vlan } reject
                      return
                    }

                    chain forward {
                      iifname { wan, $ixps } oifname base jump filter-routing
                      oifname $ixps jump ixp
                      iifname base oifname { base, wan, $ixps } accept
                      oifname { as211024, kelder } accept
                    }
                    chain output {
                      oifname ifog ether type != vlan reject
                      oifname $ixps jump ixp
                    }
                  }
                  table inet nat {
                    chain prerouting {
                      ${matchInet "meta l4proto { udp, tcp } th dport domain redirect to :5353" "estuary"}
                      ip daddr ${allAssignments.shill.internal.ipv4.address} tcp dport { http, https } dnat to ${allAssignments.middleman.internal.ipv4.address}
                      ip6 daddr ${allAssignments.shill.internal.ipv6.address} tcp dport { http, https } dnat to ${allAssignments.middleman.internal.ipv6.address}
                    }
                    chain postrouting {
                      ip saddr ${prefixes.all.v4} snat to ${assignments.internal.ipv4.address}
                    }
                  }
                '';
              };
            };
          }
          (mkIf config.my.build.isDevVM {
            systemd.network = {
              netdevs."05-dummy-base".netdevConfig = {
                Name = "base";
                Kind = "dummy";
              };
            };
          })
        ];
      };
  };
}
