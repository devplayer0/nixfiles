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
      inherit (lib.my.c.home) vlans;

      lanLink = {
        matchConfig = {
          Driver = "mlx5_core";
          PermanentMACAddress = "52:54:00:8a:8a:f2";
        };
        linkConfig = {
          Name = "lan";
          MTUBytes = toString lib.my.c.home.hiMTU;
        };
      };
    in
    {
      imports = [
        "${modulesPath}/profiles/qemu-guest.nix"
      ];

      config = {
        boot = {
          kernelModules = [ "kvm-intel" ];
          kernelParams = [ "console=ttyS0,115200n8" ];
          initrd = {
            availableKernelModules = [
              "virtio_pci" "ahci" "sr_mod" "virtio_blk"
              "ib_core" "ib_uverbs" "mlx5_core" "mlx5_ib" "8021q"
              "rdma_cm" "iw_cm" "ib_cm" "nvme_core" "nvme_rdma"
            ];
            kernelModules = [ "dm-snapshot" "nvme-fabrics" ];
            systemd = {
              extraBin = with pkgs; {
                dmesg = "${util-linux}/bin/dmesg";
                ip = "${iproute2}/bin/ip";
                nvme = "${nvme-cli}/bin/nvme";
              };
              extraConfig = ''
                DefaultTimeoutStartSec=50
                DefaultDeviceTimeoutSec=50
              '';
              network = {
                enable = true;
                wait-online.enable = true;

                links."10-lan" = lanLink;
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

              services.connect-nvme = {
                description = "Connect NVMe-oF";
                before = [ "initrd-root-device.target" ];
                after = [ "systemd-networkd-wait-online.service" ];
                requires = [ "systemd-networkd-wait-online.service" ];

                serviceConfig = {
                  Type = "oneshot";
                  Restart = "on-failure";
                  RestartSec = 10;
                };
                script = ''
                  ${pkgs.nvme-cli}/bin/nvme connect -t rdma -a 192.168.68.80 \
                    -n nqn.2016-06.io.spdk:river -q nqn.2014-08.org.nvmexpress:uuid:12b52d80-ccb6-418d-9b2e-2be34bff3cd9
                '';

                wantedBy = [ "initrd-root-device.target" ];
              };
            };
          };
        };

        hardware = {
          enableRedistributableFirmware = true;
          cpu = {
            intel.updateMicrocode = true;
          };
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

            "10-lan" = lanLink;
          };

          # So we don't drop the IP we use to connect to NVMe-oF!
          networks."60-lan-hi".networkConfig.KeepConfiguration = "static";
        };

        my = {
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP9uFa4z9WPuXRFVA+PClQSitQCSPckhKTxo1Hq585Oa";
          };
          server.enable = true;
          deploy.node.hostname = "192.168.68.1";
        };
      };
    };
  };
}
