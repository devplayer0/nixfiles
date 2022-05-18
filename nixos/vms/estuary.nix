{
  nixos.systems.estuary = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "unstable";

    assignments.internal = {
      name = "estuary-vm";
      altNames = [ "fw" ];
      ipv4 = {
        address = "10.100.0.1";
        gateway = null;
      };
      ipv6.address = "2a0e:97c0:4d1:0::1";
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        config = mkMerge [
          {
            networking.domain = "nl1.int.nul.ie";

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
                #"80-wan" = {
                #  matchConfig.Name = "wan";
                #  address = [
                #    "1.2.3.4/24"
                #    "2a00::2/64"
                #  ];
                #};
                "80-wan" = {
                  matchConfig.Name = "wan";
                  DHCP = "ipv4";
                };
                "80-base" = mkMerge [
                  (networkdAssignment "base" assignments.internal)
                  {
                    networkConfig = {
                      IPv6AcceptRA = mkForce false;
                      IPv6SendRA = true;
                      IPMasquerade = "both";
                    };
                    ipv6SendRAConfig.DNS = [ assignments.internal.ipv6.address ];
                    ipv6Prefixes = [
                      {
                        ipv6PrefixConfig.Prefix = "2a0e:97c0:4d1:0::/64";
                      }
                    ];
                  }
                ];
              };
            };

            my = {
              server.enable = true;

              firewall = {
                trustedInterfaces = [ "base" ];
                nat = {
                  enable = true;
                  externalInterface = "wan";
                };
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
