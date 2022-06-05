{ lib, ... }: {
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
          address = "188.141.14.75";
          gateway = null;
          genPTR = false;
        };
        ipv6 = {
          address = "2a0e:97c0:4d0:bbbf::1";
          gateway = "fe80::215:17ff:fe4b:494a";
        };
      };
      base = {
        ipv4 = {
          address = "${lib.my.colony.start.base.v4}1";
          gateway = null;
        };
        ipv6.address = "${lib.my.colony.start.base.v6}1";
      };
    };

    configuration = { lib, pkgs, modulesPath, config, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ./dns.nix ];

        config = mkMerge [
          {
            boot.kernelParams = [ "console=ttyS0,115200n8" ];
            fileSystems = {
              "/boot" = {
                device = "/dev/disk/by-label/ESP";
                fsType = "vfat";
              };
              "/nix" = {
                device = "/dev/main/nix";
                fsType = "ext4";
              };
              "/persist" = {
                device = "/dev/main/persist";
                fsType = "ext4";
                neededForBoot = true;
              };
            };

            services = {
              lvm = {
                dmeventd.enable = true;
              };
            };

            systemd.network = {
              links = {
                "10-wan" = {
                  matchConfig.MACAddress = "52:54:00:a1:b2:5f";
                  linkConfig.Name = "wan";
                };
                "10-base" = {
                  matchConfig.MACAddress = "52:54:00:ab:f1:52";
                  linkConfig.Name = "base";
                };
              };

              networks = {
                "80-wan" = {
                  matchConfig.Name = "wan";
                  DHCP = "ipv4";
                  dhcpV4Config = {
                    UseDNS = false;
                    UseHostname = false;
                  };
                  address = [
                    (with assignments.internal.ipv6; "${address}/${toString mask}")
                  ];
                  gateway = [
                    assignments.internal.ipv6.gateway
                  ];
                  networkConfig.IPv6AcceptRA = false;
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
                    routes = map (r: { routeConfig = r; }) [
                      {
                        Gateway = allAssignments.colony.internal.ipv4.address;
                        Destination = lib.my.colony.prefixes.vms.v4;
                      }
                      {
                        Gateway = allAssignments.colony.internal.ipv6.address;
                        Destination = lib.my.colony.prefixes.vms.v6;
                      }

                      {
                        Gateway = allAssignments.colony.internal.ipv4.address;
                        Destination = lib.my.colony.prefixes.ctrs.v4;
                      }
                      {
                        Gateway = allAssignments.colony.internal.ipv6.address;
                        Destination = lib.my.colony.prefixes.ctrs.v6;
                      }
                    ];
                  }
                ];
              };
            };

            my = {
              #deploy.generate.system.mode = "boot";
              secrets.key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPhxM5mnguExkcLue47QKk1vA72OoPc3HOqqoHqHHfa1";
              server.enable = true;

              firewall = {
                trustedInterfaces = [ "base" ];
                udp.allowed = [ 5353 ];
                tcp.allowed = [ 5353 ];
                nat = {
                  enable = true;
                  externalInterface = "wan";
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
                  table inet filter {
                    chain routing-tcp {
                      # Safe enough to allow all SSH
                      tcp dport ssh accept

                      ${matchInet "tcp dport { http, https } accept" "middleman"}

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
                    chain forward {
                      iifname wan oifname base jump filter-routing
                    }
                  }
                  table inet nat {
                    chain prerouting {
                      iifname wan meta l4proto { udp, tcp } th dport domain redirect to :5353
                    }
                    chain postrouting {
                      ip saddr ${lib.my.colony.prefixes.all.v4} masquerade
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
