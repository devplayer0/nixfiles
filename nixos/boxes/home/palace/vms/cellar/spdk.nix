{ lib, pkgs, config, assignments, ... }:
let
  inherit (lib) mapAttrsToList;
in
{
  config = {
    boot.blacklistedKernelModules = [ "nvme" ];

    systemd.services = {
      spdk-tgt.after = [ "systemd-networkd-wait-online@lan-hi.service" ];
    };

    my = {
      spdk = {
        enable = true;
        extraArgs = "--mem-channels 2 --cpumask 0xffff";
        debugCommands = ''
          spdk-rpc bdev_nvme_attach_controller -t pcie -a 02:00.0 -b NVMe0
          spdk-rpc bdev_nvme_attach_controller -t pcie -a 03:00.0 -b NVMe1
          spdk-rpc bdev_nvme_attach_controller -t pcie -a 04:00.0 -b NVMe2
          spdk-rpc bdev_raid_create -n NVMeRaid -z 64 -r 0 -b 'NVMe0n1 NVMe1n1 NVMe2n1'

          spdk-rpc ublk_create_target
          spdk-rpc ublk_start_disk NVMeRaid 1
        '';
        config.subsystems =
        let
          nvmeAttaches = mapAttrsToList (name: bdf: {
            method = "bdev_nvme_attach_controller";
            params = {
              hostnqn =
                "nqn.2014-08.org.nvmexpress:uuid:2b16606f-b82c-49f8-9b20-a589dac8b775";
              trtype = "PCIe";
              inherit name;
              traddr = bdf;
            };
          }) {
            "NVMe0" = "02:00.0";
            "NVMe1" = "03:00.0";
            "NVMe2" = "04:00.0";
          };

          nvmfListener = nqn: {
            method = "nvmf_subsystem_add_listener";
            params = {
              inherit nqn;
              listen_address = {
                adrfam = "IPv4";
                traddr = assignments.hi.ipv4.address;
                trsvcid = "4420";
                trtype = "RDMA";
              };
              secure_channel = false;
            };
          };
          nvmfBdev = { nqn, hostnqn, bdev, serial }: [
            {
              method = "nvmf_create_subsystem";
              params = {
                inherit nqn;
                serial_number = serial;
              };
            }
            (nvmfListener nqn)
            {
              method = "nvmf_subsystem_add_host";
              params = {
                inherit nqn;
                host = hostnqn;
              };
            }
            {
              method = "nvmf_subsystem_add_ns";
              params = {
                inherit nqn;
                namespace = {
                  bdev_name = bdev;
                  nsid = 1;
                };
              };
            }
          ];
        in
        {
          scheduler = [
            {
              method = "framework_set_scheduler";
              params.name = "dynamic";
            }
          ];

          bdev = [
            {
              method = "bdev_set_options";
              params.bdev_auto_examine = false;
            }
          ] ++ nvmeAttaches ++ [
            {
              method = "bdev_raid_create";
              params = {
                base_bdevs = [ "NVMe0n1" "NVMe1n1" "NVMe2n1" ];
                name = "NVMeRaid";
                raid_level = "raid0";
                strip_size_kb = 64;
              };
            }
            {
              method = "bdev_examine";
              params.name = "NVMeRaid";
            }
            { method = "bdev_wait_for_examine"; }
          ];

          nvmf = [
            {
              method = "nvmf_create_transport";
              params.trtype = "RDMA";
            }
            (nvmfListener "nqn.2014-08.org.nvmexpress.discovery")
          ] ++ (nvmfBdev {
            bdev = "NVMeRaidp1";
            nqn = "nqn.2016-06.io.spdk:river";
            hostnqn =
              "nqn.2014-08.org.nvmexpress:uuid:12b52d80-ccb6-418d-9b2e-2be34bff3cd9";
            serial = "SPDK00000000000001";
          }) ++ (nvmfBdev {
            bdev = "NVMeRaidp2";
            nqn = "nqn.2016-06.io.spdk:castle";
            hostnqn =
              "nqn.2014-08.org.nvmexpress:uuid:2230b066-a674-4f45-a1dc-f7727b3a9e7b";
            serial = "SPDK00000000000002";
          }) ++ (nvmfBdev {
            bdev = "NVMeRaidp3";
            nqn = "nqn.2016-06.io.spdk:sfh";
            hostnqn =
              "nqn.2014-08.org.nvmexpress:uuid:85d7df36-0de0-431b-b06e-51f7c0a455b4";
            serial = "SPDK00000000000003";
          });
        };
      };
    };
  };
}
