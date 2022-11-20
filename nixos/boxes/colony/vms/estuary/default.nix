{ lib, ... }:
let
  pubV4 = "94.142.240.44";
in
{
  nixos = {
    vpns = {
      l2 = {
        as211024 = {
          vni = 211024;
          peers = {
            estuary.addr = pubV4;
            home.addr = "109.255.1.83";
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
        domain = lib.my.colony.domain;
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
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.base.v4}1";
          gateway = null;
        };
        ipv6.address = "${lib.my.colony.start.base.v6}1";
      };
      as211024 = {
        ipv4 = {
          address = "10.255.3.1";
          gateway = null;
        };
        ipv6.address = "2a0e:97c0:4df:0:3::1";
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
              ];
            };

            services = {
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
              services = {
                # Use this as a way to make sure the router always knows we're here (NDP seems kindy funky)
                ipv6-neigh-keepalive =
                let
                  waitOnline = "systemd-networkd-wait-online@wan.service";
                in
                {
                  description = "Frequent ICMP6 neighbour solicitations";
                  enable = false;
                  requires = [ waitOnline ];
                  after = [ waitOnline ];
                  script = ''
                    while true; do
                      ${pkgs.ndisc6}/bin/ndisc6 ${assignments.internal.ipv6.gateway} wan
                      sleep 10
                    done
                  '';
                  wantedBy = [ "multi-user.target" ];
                };

                bird2 =
                let
                  waitOnline = "systemd-networkd-wait-online@wan.service";
                in
                {
                  after = [ waitOnline ];
                  requires = [ waitOnline ];
                };
              };
            };

            #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
            systemd.network = {
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
                (mkVLAN "ifog" 409)

                (mkVLAN "frys-ix" 701)
                (mkVLAN "nl-ix" 1845)
                (mkVLAN "fogixp" 1147)
                (mkVLAN "ifog-transit" 702)
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
                        ipv6PrefixConfig.Prefix = lib.my.colony.prefixes.base.v6;
                      }
                    ];
                    routes = map (r: { routeConfig = r; }) (flatten
                      ([  ] ++
                      (map (pName: [
                        {
                          Gateway = allAssignments.colony.internal.ipv4.address;
                          Destination = lib.my.colony.prefixes."${pName}".v4;
                        }
                        {
                          Gateway = allAssignments.colony.internal.ipv6.address;
                          Destination = lib.my.colony.prefixes."${pName}".v6;
                        }
                      ]) [ "vms" "ctrs" "oci" ])));
                  }
                ];

                "90-l2mesh-as211024" = {
                  address = with assignments.as211024; [
                    (with ipv4; "${address}/${toString mask}")
                    (with ipv6; "${address}/${toString mask}")
                  ];
                  networkConfig.IPv6AcceptRA = false;
                };
              } ];
            };

            my = {
              #deploy.generate.system.mode = "boot";
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF9up7pXu6M/OWCKufTOfSiGcxMUk4VqUe7fLuatNFFA";
              server.enable = true;

              firewall = {
                trustedInterfaces = [ "base" "as211024" ];
                udp.allowed = [ 5353 ];
                tcp.allowed = [ 5353 "bgp" ];
                nat = {
                  enable = true;
                  externalInterface = "wan";
                  forwardPorts = [
                    {
                      port = "http";
                      dst = allAssignments.middleman.internal.ipv4.address + ":http";
                    }
                    {
                      port = "https";
                      dst = allAssignments.middleman.internal.ipv4.address + ":https";
                    }
                    {
                      port = 8448;
                      dst = allAssignments.middleman.internal.ipv4.address + ":8448";
                    }

                    {
                      port = 2456;
                      dst = allAssignments.valheim-oci.internal.ipv4.address + ":2456";
                      proto = "udp";
                    }
                    {
                      port = 2457;
                      dst = allAssignments.valheim-oci.internal.ipv4.address + ":2457";
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
                      tcp flags & (fin|syn|rst|ack) == syn ct state new jump routing-tcp
                      meta l4proto udp ct state new jump routing-udp
                      return
                    }
                    chain ixp {
                      ether type != { ip, ip6, arp, vlan } reject
                      return
                    }

                    chain forward {
                      iifname wan oifname base jump filter-routing
                      iifname ixps oifname base jump filter-routing
                      oifname ixps jump ixp
                      oifname as211024 accept
                    }
                    chain output {
                      oifname ifog ether type != vlan reject
                      oifname ixps jump ixp
                    }
                  }
                  table inet nat {
                    chain prerouting {
                      ${matchInet "meta l4proto { udp, tcp } th dport domain redirect to :5353" "estuary"}
                    }
                    chain postrouting {
                      ip saddr ${lib.my.colony.prefixes.all.v4} snat to ${assignments.internal.ipv4.address}
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
