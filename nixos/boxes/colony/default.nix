{ lib, ... }: {
  imports = [ ./vms ];

  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      internal = {
        altNames = [ "vm" ];
        domain = lib.my.colony.domain;
        ipv4.address = "${lib.my.colony.start.base.v4}2";
        ipv6 = {
          iid = "::2";
          address = "${lib.my.colony.start.base.v6}2";
        };
      };
      vms = {
        name = "colony-vms";
        domain = lib.my.colony.domain;
        ipv4 = {
          address = "${lib.my.colony.start.vms.v4}1";
          gateway = null;
        };
        ipv6.address = "${lib.my.colony.start.vms.v6}1";
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkIf mkMerge mkForce;
        inherit (lib.my) networkdAssignment;
      in
      {
        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            amd.updateMicrocode = true;
          };
        };

        boot = {
          kernelPackages = pkgs.linuxKernel.packages.linux_5_15.extend (self: super: {
            kernel = super.kernel.override {
              structuredExtraConfig = with lib.kernel; {
                #SOME_OPT = yes;
                #A_MOD = module;
              };
            };
          });
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "amd_iommu=on" "console=ttyS0,115200n8" "console=ttyS1,115200n8" "console=tty0" ];
          initrd = {
            availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-uuid/C1C9-9CBC";
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

          netdata = {
            enable = true;
            config = {
              # Ignore the VCCM sensor (RAM voltage is 1.35V with XMP enabled)
              "plugin:freeipmi"."command options" = "ignore 5";
            };
          };

          smartd = {
            enable = true;
            autodetect = true;
            extraOptions = [ "-A /var/log/smartd/" "--interval=600" ];
          };
        };

        environment.systemPackages = with pkgs; [
          pciutils
          usbutils
          partclone
          lm_sensors
          linuxPackages.cpupower
          smartmontools
          xfsprogs
        ];

        systemd = {
          services = {
            "serial-getty@ttyS0".enable = true;
            "serial-getty@ttyS1".enable = true;
          };

          tmpfiles.rules = [
            "d /var/log/smartd 0755 root root"
          ];

          network = {
            links = {
              "10-wan0" = {
                matchConfig.MACAddress = "d0:50:99:fa:a7:99";
                linkConfig.Name = "wan0";
              };
              "10-wan1" = {
                matchConfig.MACAddress = "d0:50:99:fa:a7:9a";
                linkConfig.Name = "wan1";
              };
            };
            netdevs = {
              "25-base".netdevConfig = {
                Name = "base";
                Kind = "bridge";
              };
              "30-base-dummy".netdevConfig = {
                Name = "base0";
                Kind = "dummy";
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
              "80-base-dummy" = {
                matchConfig.Name = "base0";
                networkConfig.Bridge = "base";
              };
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
                    DNS = [ allAssignments.estuary.base.ipv6.address ];
                    Domains = [ config.networking.domain ];
                  };
                  ipv6Prefixes = [
                    {
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

                    {
                      Gateway = allAssignments.whale2.internal.ipv4.address;
                      Destination = lib.my.colony.prefixes.oci.v4;
                    }
                    {
                      Gateway = allAssignments.whale2.internal.ipv6.address;
                      Destination = lib.my.colony.prefixes.oci.v6;
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
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIijqzAWF6OxKr4aeCa1TAc5xGn4rdIjVTt0wAPU6uY";
          };

          server.enable = true;

          firewall = {
            trustedInterfaces = [ "vms" ];
            extraRules = ''
              table inet filter {
                chain forward {
                  # Trust that the outer firewall has done the filtering!
                  iifname base oifname vms accept
                }
              }
            '';
          };
        };
      };
  };
}
