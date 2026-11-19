{ lib, ... }:
let
  inherit (lib.my) net mkVLAN;
  inherit (lib.my.c) pubDomain;
  inherit (lib.my.c.home) domain vlans prefixes vips vlanDns hiMTU;
in
{
  imports = [ ./slop-broker.nix ./vms ];

  nixos.systems.palace = {
    system = "x86_64-linux";
    nixpkgs = "mine-stable";
    home-manager = "mine-stable";

    assignments = {
      hi = {
        inherit domain;
        mtu = hiMTU;
        ipv4 = {
          address = net.cidr.host 22 prefixes.hi.v4;
          mask = 22;
          gateway = vips.hi.v4;
        };
        ipv6 = {
          iid = "::2:1";
          address = net.cidr.host (65536*2+1) prefixes.hi.v6;
        };
      };
      core = {
        inherit domain;
        name = "palace-core";
        mtu = 1500;
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
        inherit (lib.my.c) networkd;
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
          kernelModules = [ "dm-raid" "kvm-amd" "nvme-rdma" ];
          kernelParams = [ "amd_iommu=on" ];
          initrd = {
            availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "usbhid" "sd_mod" "sr_mod" ];
            # LVM autoactivation can discover the RAID LVs before stage-two module loading.
            kernelModules = [ "dm-raid" ];
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

        # NVMe-oF disks connected here belong to guests (`palace` has no NVMe of its own; its
        # drives are passed to `cellar`); never activate their volume groups
        environment.etc."lvm/lvm.conf".text = ''
          devices/global_filter = [ "r|^/dev/nvme|" "a|.*|" ]
        '';

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
            ACTION=="add", SUBSYSTEM=="net", ENV{ID_NET_DRIVER}=="mlx5_core", ENV{ID_PATH}=="pci-0000:44:00.0", ATTR{device/sriov_numvfs}="6"
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

        networking = { inherit domain; };

        systemd = {
          tmpfiles.rules = [
            "d /var/log/smartd 0755 root root"
          ];

          network = {
            links = {
              "10-river-jim-phy" = {
                matchConfig = {
                  PermanentMACAddress = "e0:d5:5e:68:0c:6e";
                  Driver = "igb";
                };
                linkConfig.Name = "river-jim-phy";
              };
              "10-host-jim" = {
                matchConfig.PermanentMACAddress = "e0:d5:5e:68:0c:70";
                linkConfig.Name = "host-jim";
              };
              "10-uplink-dave" = {
                matchConfig = {
                  PermanentMACAddress = "24:8a:07:ac:59:c0";
                  Driver = "mlx5_core";
                };
                linkConfig = {
                  Name = "uplink-dave";
                  MTUBytes = toString hiMTU;
                };
              };
            };

            netdevs = mkMerge [
              (mkVLAN "lan-hi" vlans.hi)
              (mkVLAN "lan-lo-phy" vlans.lo)
              {
                "25-lan-core".netdevConfig = {
                  Name = "lan-core";
                  Kind = "bridge";
                };
              }
              {
                "25-lan-lo".netdevConfig = {
                  Name = "lan-lo";
                  Kind = "bridge";
                };
              }
            ];

            networks = {
              "50-lan-core" = mkMerge [
                (networkdAssignment "lan-core" assignments.core)
                {
                  matchConfig.Name = "lan-core";
                  vlan = [ "lan-lo-phy" ];
                  networkConfig.IPv6AcceptRA = mkForce false;
                }
              ];

              "50-uplink-dave" = {
                matchConfig.Name = "uplink-dave";
                vlan = [ "lan-hi" ];
                networkConfig = networkd.noL3;
                linkConfig.RequiredForOnline = "no";
                extraConfig = ''
                  # cellar
                  [SR-IOV]
                  VirtualFunction=0
                  VLANId=${toString vlans.hi}
                  LinkState=yes
                  MACAddress=52:54:00:cc:3e:70

                  # river RDMA
                  [SR-IOV]
                  VirtualFunction=1
                  VLANId=${toString vlans.hi}
                  LinkState=yes
                  MACAddress=52:54:00:8a:8a:f2

                  # sfh
                  [SR-IOV]
                  VirtualFunction=2
                  VLANId=${toString vlans.hi}
                  LinkState=yes
                  MACAddress=52:54:00:ac:15:a9

                  # sfh containers
                  [SR-IOV]
                  VirtualFunction=3
                  VLANId=${toString vlans.hi}
                  LinkState=yes
                  MACAddress=52:54:00:90:34:95

                  # river LAN trunk
                  [SR-IOV]
                  VirtualFunction=4
                  LinkState=auto
                  MACAddress=52:54:00:8a:8a:f4
                  Trust=yes
                  MACSpoofCheck=no

                  # slop-cannon (untrusted)
                  [SR-IOV]
                  VirtualFunction=5
                  VLANId=${toString vlans.untrusted}
                  LinkState=auto
                  MACAddress=52:54:00:71:22:ea
                  MACSpoofCheck=yes
                '';
              };
              "60-lan-hi" = mkMerge [
                (networkdAssignment "lan-hi" assignments.hi)
                { networkConfig = vlanDns "hi"; }
              ];

              "50-host-jim" = {
                matchConfig.Name = "host-jim";
                networkConfig = {
                  Bridge = "lan-core";
                } // networkd.noL3;
              };
              "50-lan-lo-phy" = {
                matchConfig.Name = "lan-lo-phy";
                networkConfig = {
                  Bridge = "lan-lo";
                } // networkd.noL3;
              };
              "60-lan-lo" = {
                matchConfig.Name = "lan-lo";
                linkConfig.RequiredForOnline = "no";
                networkConfig = networkd.noL3;
              };
            };
          };
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHzVJpoDz/AAYLJGzU8t6DgZ2sY3oehRqrlSO7C+GWiK";
          };

          server.enable = true;
          deploy.node.hostname = "192.168.68.22";

          # Host NQN for guest disks on `cellar`; nothing on `palace` itself boots from it
          nvme.uuid = "a5b573fe-59e0-4760-802d-4b6d2df6dcf2";
        };
      };
  };
}
