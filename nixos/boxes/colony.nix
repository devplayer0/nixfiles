{
  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "unstable";

    configuration = { lib, pkgs, modulesPath, config, systems, ... }:
      let
        inherit (lib) mkIf;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINkqdN5t3UKwrNOOPKlbnG1WYhnkV5H9luAzMotr8SbT";
            files."test.txt" = {};
          };

          firewall = {
            trustedInterfaces = [ "virtual" ];
            nat = {
              externalInterface = "eth0";
              forwardPorts = [
                {
                  proto = "tcp";
                  sourcePort = 2222;
                  destination = "127.0.0.1:22";
                }
              ];
            };
          };
          server.enable = true;

          containers = {
            instances.vaultwarden = {
              networking.bridge = "virtual";
            };
          };
          vms = {
            instances.test = {
              networks.virtual = {};
              drives = {
                disk = {
                  backend = {
                    driver = "file";
                    filename = "${systems.installer.configuration.config.my.buildAs.iso}/iso/nixos.iso";
                    read-only = "on";
                  };
                  format.driver = "raw";
                  frontend = "ide-cd";
                  frontendOpts = {
                    bootindex = 0;
                  };
                };
              };
            };
          };
        };

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

        networking = {
          interfaces = mkIf (!config.my.build.isDevVM) {
            enp1s0.useDHCP = true;
          };
        };

        systemd.network = {
          netdevs."25-virtual-bridge".netdevConfig = {
            Name = "virtual";
            Kind = "bridge";
          };
          networks."80-virtual-bridge" = {
            matchConfig = {
              Name = "virtual";
              Driver = "bridge";
            };
            networkConfig = {
              Address = "172.16.137.1/24";
              DHCPServer = true;
              # TODO: Configuration for routed IPv6 (and maybe IPv4)
              IPMasquerade = "both";
              IPv6SendRA = true;
            };
          };
        };

        #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
        virtualisation = {
          cores = 8;
          memorySize = 8192;
        };
      };
  };
}
