{
  imports = [ (import ../../routing-common 0) ];

  config.nixos.systems.river = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "mine";

    configuration = { lib, modulesPath, pkgs, config, assignments, allAssignments, ... }:
    let
      inherit (lib.my) networkdAssignment mkVLAN;
      inherit (lib.my.c) networkd;
      inherit (lib.my.c.home) vlans domain prefixes roceBootModules;
    in
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
      ];

      config = {
        boot = {
          kernelModules = [ "kvm-amd" ];
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            availableKernelModules = [
              "virtio_pci" "ahci" "sr_mod" "virtio_blk"
              "8021q"
            ] ++ roceBootModules;
            kernelModules = [ "dm-snapshot" ];
            systemd = {
              network = {
                # Don't need to put the link config here, they're copied from main config
                netdevs = mkVLAN "lan-hi" vlans.hi;
                networks = {
                  "20-lan" = {
                    matchConfig.Name = "lan";
                    vlan = [ "lan-hi" ];
                    linkConfig.RequiredForOnline = "no";
                    networkConfig = networkd.noL3;
                  };
                  "30-lan-hi" = networkdAssignment "lan-hi" assignments.hi;
                };
              };
            };
          };
        };

        hardware = {
          enableRedistributableFirmware = true;
        };

        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-partuuid/3ec6c49e-b485-40cb-8eff-315581ac6fe9";
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
            boot.thin.enable = true;
            dmeventd.enable = true;
          };
          fstrim.enable = true;
        };

        systemd.network = {
          links = {
            "10-wan" = {
              matchConfig = {
                # Matching against MAC address seems to break VLAN interfaces
                # (since they share the same MAC address)
                Driver = "virtio_net";
                PermanentMACAddress = "e0:d5:5e:68:0c:6e";
              };
              linkConfig = {
                Name = "wan";
                RxBufferSize = 4096;
                TxBufferSize = 4096;
              };
            };

            "10-lan" = {
              matchConfig = {
                Driver = "mlx5_core";
                PermanentMACAddress = "52:54:00:8a:8a:f2";
              };
              linkConfig = {
                Name = "lan";
                MTUBytes = toString lib.my.c.home.hiMTU;
              };
            };
          };

          # So we don't drop the IP we use to connect to NVMe-oF!
          networks."60-lan-hi".networkConfig.KeepConfiguration = "static";
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9uFa4z9WPuXRFVA+PClQSitQCSPckhKTxo1Hq585Oa";
          };
          server.enable = true;
          nvme = {
            uuid = "12b52d80-ccb6-418d-9b2e-2be34bff3cd9";
            boot = {
              nqn = "nqn.2016-06.io.spdk:river";
              address = "192.168.68.80";
            };
          };

          netboot.server = {
            enable = true;
            ip = assignments.lo.ipv4.address;
            host = "boot.${domain}";
            allowedPrefixes = with prefixes; [ hi.v4 hi.v6 lo.v4 lo.v6 ];
            instances = [ "sfh" ];
          };

          deploy.node.hostname = "192.168.68.1";
        };
      };
    };
  };
}
