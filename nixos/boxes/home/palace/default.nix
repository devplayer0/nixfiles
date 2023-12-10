{ lib, ... }:
let
  inherit (lib.my) net mkVLAN;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain vlans prefixes vips;
in
{
  imports = [ ./vms ];

  nixos.systems.palace = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      hi = {
        inherit domain;
        ipv4 = {
          address = net.cidr.host 22 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
      };
      core = {
        inherit domain;
        name = "palace-core";
        ipv4 = {
          address = net.cidr.host 20 prefixes.core.v4;
          gateway = null;
        };
      };
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, allAssignments, ... }:
      let
        inherit (lib) mkForce mkMerge;
        inherit (lib.my) networkdAssignment;
      in
      {
        boot = {
          kernelPackages = (lib.my.c.kernel.lts pkgs).extend (self: super: {
            kernel = super.kernel.override {
              structuredExtraConfig = with lib.kernel; {
                ACPI_APEI_PCIEAER = yes;
                PCIEAER = yes;
              };
            };
          });
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "amd_iommu=on" ];
          initrd = {
            availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
          };
        };

        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            amd.updateMicrocode = true;
          };
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/c06a8d24-2af9-4416-bf5e-cfe6defdbd47";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/disk/by-uuid/450e1f72-238a-4160-98b8-b5e6d0d6fdf6";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/disk/by-uuid/9d6d53a8-dff8-49e0-9bc3-fb5f7c6760d0";
            fsType = "ext4";
            neededForBoot = true;
          };
        };

        services = {
          lvm = {
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          smartd = {
            enable = true;
            autodetect = true;
            extraOptions = [ "-A /var/log/smartd/" "--interval=600" ];
          };
          udev.extraRules = ''
            ACTION=="add", SUBSYSTEM=="net", ENV{ID_NET_DRIVER}=="mlx5_core", ENV{ID_PATH}=="pci-0000:44:00.0", ATTR{device/sriov_numvfs}="3"
          '';
        };

        environment.systemPackages = with pkgs; [
          pciutils
          usbutils
          partclone
          lm_sensors
          linuxPackages.cpupower
          smartmontools
          mstflint
          ethtool
          hwloc
        ];

        networking.domain = "h.${pubDomain}";

        systemd = {
          tmpfiles.rules = [
            "d /var/log/smartd 0755 root root"
          ];

          network = {
            links = {
              "10-et1g0" = {
                matchConfig.MACAddress = "e0:d5:5e:68:0c:6e";
                linkConfig.Name = "et1g0";
              };
              "10-lan-core" = {
                matchConfig.MACAddress = "e0:d5:5e:68:0c:70";
                linkConfig.Name = "lan-core";
              };
              "10-et100g" = {
                matchConfig = {
                  PermanentMACAddress = "24:8a:07:ac:59:c0";
                  Driver = "mlx5_core";
                };
                linkConfig = {
                  Name = "et100g";
                  MTUBytes = "9000";
                };
              };
            };

            netdevs = mkMerge [
              (mkVLAN "lan-hi" vlans.hi)
            ];

            networks = {
              "50-lan-core" = mkMerge [
                (networkdAssignment "lan-core" assignments.core)
                {
                  matchConfig.Name = "lan-core";
                  networkConfig.IPv6AcceptRA = mkForce false;
                }
              ];

              "50-et100g" = {
                matchConfig.Name = "et100g";
                vlan = [ "lan-hi" ];
                networkConfig.IPv6AcceptRA = false;
                extraConfig = ''
                  # cellar
                  [SR-IOV]
                  VirtualFunction=0
                  VLANId=${toString vlans.hi}
                  LinkState=yes
                  MACAddress=52:54:00:cc:3e:70
                '';
              };
              "60-lan-hi" = mkMerge [
                (networkdAssignment "lan-hi" assignments.hi)
                {
                  matchConfig.Name = "lan-hi";
                  linkConfig.MTUBytes = "9000";
                  networkConfig.DNS = [
                    (allAssignments.stream.hi.ipv4.address)
                    # (allAssignments.river.hi.ipv4.address)
                  ];
                }
              ];
            };
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzVJpoDz/AAYLJGzU8t6DgZ2sY3oehRqrlSO7C+GWiK";
          };

          server.enable = true;
          deploy.node.hostname = "192.168.68.22";
        };
      };
  };
}
