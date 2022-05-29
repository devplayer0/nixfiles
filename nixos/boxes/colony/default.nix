{
  imports = [ ./vms ];

  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      internal = {
        altNames = [ "vm" ];
        ipv4.address = "10.100.0.2";
        #ipv6.address = "2a0e:97c0:4d1:0::2";
        ipv6 = rec {
          iid = "::2";
          address = "2a0e:97c0:4d0:bbb0${iid}";
        };
      };
      vms = {
        ipv4 = {
          address = "10.100.1.1";
          gateway = null;
        };
        #ipv6.address = "2a0e:97c0:4d1:1::1";
        ipv6.address = "2a0e:97c0:4d0:bbb1::1";
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        networking.domain = lib.my.colony.domain;

        boot.kernelParams = [ "intel_iommu=on" ];
        boot.loader.systemd-boot.configurationLimit = 20;
        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-label/ESP";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/ssds/colony-nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/ssds/colony-persist";
            fsType = "ext4";
            neededForBoot = true;
          };
        };
        services = {
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
        };

        environment.systemPackages = with pkgs; [
          pciutils
        ];

        systemd = {
          network = {
            links = {
              "10-base-ext" = {
                matchConfig.MACAddress = "52:54:00:81:bd:a1";
                linkConfig.Name = "base-ext";
              };
            };
            netdevs = {
              "25-base".netdevConfig = {
                Name = "base";
                Kind = "bridge";
              };

              "25-vms".netdevConfig = {
                Name = "vms";
                Kind = "bridge";
              };
              "30-vms-dummy".netdevConfig = {
                Name = "vms0";
                Kind = "dummy";
              };
            };

            networks = {
              "80-base" = networkdAssignment "base" assignments.internal;
              "80-base-ext" = {
                matchConfig.Name = "base-ext";
                networkConfig.Bridge = "base";
              };

              "80-vms" = mkMerge [
                (networkdAssignment "vms" assignments.vms)
                {
                  networkConfig = {
                    IPv6AcceptRA = mkForce false;
                    IPv6SendRA = true;
                  };
                  ipv6SendRAConfig = {
                    DNS = [ allAssignments.estuary.internal.ipv6.address ];
                    Domains = [ config.networking.domain ];
                  };
                  ipv6Prefixes = [
                    {
                      #ipv6PrefixConfig.Prefix = "2a0e:97c0:4d1:1::/64";
                      ipv6PrefixConfig.Prefix = lib.my.colony.prefixes.vms.v6;
                    }
                  ];
                  routes = map (r: { routeConfig = r; }) [
                    {
                      Gateway = allAssignments.shill.internal.ipv4.address;
                      Destination = lib.my.colony.prefixes.ctrs.v4;
                    }
                    {
                      Gateway = allAssignments.shill.internal.ipv6.address;
                      Destination = lib.my.colony.prefixes.ctrs.v6;
                    }
                  ];
                }
              ];
              # Just so the vms interface will come up (in networkd's eyes), allowing dependant VMs to start.
              # Could tweak the `waitOnline` for a single VM, but this seems better overall?
              "80-vms-dummy" = {
                matchConfig.Name = "vms0";
                networkConfig.Bridge = "vms";
              };
            };
          };
        };

        #environment.etc."udev/udev.conf".text = "udev_log=debug";
        #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
        virtualisation = {
          cores = 8;
          memorySize = 8192;
          qemu.options = [
            "-machine q35"
            "-accel kvm,kernel-irqchip=split"
            "-device intel-iommu,intremap=on,caching-mode=on"
          ];
        };

        my = {
          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKp5WDdDr/1NS3SJIDOKwcCNZDFOxqPAD7cbZWAP7EkX";
          };

          server.enable = true;

          firewall = {
            trustedInterfaces = [ "base" "vms" ];
          };
        };
      };
  };
}
