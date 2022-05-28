{
  nixos.systems.estuary = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    assignments.internal = {
      name = "estuary-vm";
      altNames = [ "fw" ];
      ipv4 = {
        address = "10.100.0.1";
        gateway = null;
      };
      #ipv6.address = "2a0e:97c0:4d1:0::1";
      ipv6.address = "2a0e:97c0:4d0:bbb0::1";
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
            networking.domain = lib.my.colonyDomain;

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
                    "2a0e:97c0:4d0:bbbf::1/64"
                  ];
                  gateway = [
                    "fe80::215:17ff:fe4b:494a"
                  ];
                  networkConfig.IPv6AcceptRA = false;
                };
                "80-base" = mkMerge [
                  (networkdAssignment "base" assignments.internal)
                  {
                    dns = [ "127.0.0.1" "::1" ];
                    domains = [ config.networking.domain ];
                    networkConfig = {
                      IPv6AcceptRA = mkForce false;
                      IPv6SendRA = true;
                    };
                    ipv6SendRAConfig = {
                      DNS = [ assignments.internal.ipv6.address ];
                      Domains = [ config.networking.domain ];
                    };
                    ipv6Prefixes = [
                      {
                        #ipv6PrefixConfig.Prefix = "2a0e:97c0:4d1:0::/64";
                        ipv6PrefixConfig.Prefix = "2a0e:97c0:4d0:bbb0::/64";
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
                extraRules = ''
                  table inet filter {
                    chain routing-tcp {
                      # Safe enough to allow all SSH
                      tcp dport ssh accept
                    }
                    chain routing-udp {

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
                      ip saddr 10.100.0.0/16 masquerade
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
