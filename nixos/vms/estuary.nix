{
  nixos.systems.estuary = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "unstable";

    configuration = { lib, pkgs, modulesPath, config, systems, ... }:
      let
        inherit (lib) mkIf mkMerge;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

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
                "80-base" = {
                  matchConfig.Name = "base";
                  address = with config.my.network; [ "${ipv4}/24" "${ipv6}/64" ];
                  networkConfig = {
                    DHCPServer = true;
                    IPv6SendRA = true;
                    IPMasquerade = "both";
                  };
                };
              };
            };

            my = {
              server.enable = true;

              network = {
                ipv6 = "2a0e:97c0:4d1:0::1";
                ipv4 = "10.110.0.1";
              };
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
