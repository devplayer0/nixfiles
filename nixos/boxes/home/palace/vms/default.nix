{
  imports = [
    ./cellar
    ./river.nix
    ./sfh
    ./slop-cannon.nix
  ];

  nixos.systems.palace.configuration = { lib, pkgs, config, systems, allAssignments, ... }:
  let
    inherit (lib) mkMerge;
    inherit (config.my.nvme) uuid;
    inherit (lib.my) vm;
    inherit (lib.my.c) networkd;
    inherit (lib.my.c.home) hiMTU;

    installerDisk = {
      name = "installer";
      backend = {
        driver = "file";
        filename = "/persist/home/dev/nixos-installer-devplayer0.iso";
        read-only = "on";
      };
      format.driver = "raw";
      frontend = "ide-cd";
      frontendOpts = {
        bootindex = 1;
      };
    };

    # `slop-cannon`'s disk: a partition of `cellar`'s RAID, connected here so the guest never
    # speaks NVMe-oF itself
    slopDisk = {
      nqn = "nqn.2016-06.io.spdk:slop-cannon";
      device = "/dev/disk/by-id/nvme-SPDK_bdev_Controller_SPDK00000000000004";
    };
  in
  {
    systemd.network = {
      netdevs = {
        "25-river-jim-tap" = {
           netdevConfig = {
             Name = "river-jim-tap";
             Kind = "macvtap";
             MTUBytes = toString hiMTU;
           };
           # TODO: Upstream this missing section
           extraConfig = ''
             [MACVTAP]
             Mode=passthru
           '';
        };
      };
      networks = {
        "75-river-jim-phy" = {
          matchConfig.Name = "river-jim-phy";
          linkConfig = {
            RequiredForOnline = "no";
            MTUBytes = toString hiMTU;
          };
          networkConfig = {
            MACVTAP = "river-jim-tap";
          } // networkd.noL3;
        };
        "75-river-jim-tap" = {
          matchConfig.Name = "river-jim-tap";
          linkConfig = {
            RequiredForOnline = "no";
            MTUBytes = toString hiMTU;
            # Guest receive-filter changes are not synchronized to the host macvtap.
            AllMulticast = true;
          };
          networkConfig = networkd.noL3;
        };
      };
    };

    systemd.services =
    let
      awaitVM = system: {
        after = [ "vm@${system}.service" ];
        bindsTo = [ "vm@${system}.service" ];
        preStart = ''
          until ${pkgs.netcat}/bin/nc -w1 -z ${allAssignments.${system}.hi.ipv4.address} 22; do
            sleep 1
          done
        '';
      };
    in
    {
      "vm@cellar" = {
        serviceConfig = {
          CPUAffinity = "numa";
          NUMAPolicy = "bind";
          NUMAMask = "1";
        };
      };

      "vm@river" =
      let
        vtapUnit = "sys-subsystem-net-devices-river\\x2djim\\x2dtap.device";
      in
      mkMerge [
        (awaitVM "cellar")
        {
          requires = [ vtapUnit ];
          after = [ vtapUnit ];
        }
      ];
      "vm@sfh" = (awaitVM "river");

      # Only `vm@slop-cannon` needs this; stops before `cellar` does, and gives up on a dead
      # target rather than hanging I/O on `palace`
      slop-cannon-disk = mkMerge [
        (awaitVM "cellar")
        {
          description = "Connect slop-cannon's NVMe-oF disk";
          path = with pkgs; [ nvme-cli systemd ];
          script = ''
            until nvme connect -t rdma -a ${allAssignments.cellar.hi.ipv4.address} -s 4420 \
              -n ${slopDisk.nqn} -q nqn.2014-08.org.nvmexpress:uuid:${uuid} --ctrl-loss-tmo 60; do
              sleep 5
            done
            udevadm wait --timeout 30 ${slopDisk.device}
          '';
          preStop = ''
            nvme disconnect -n ${slopDisk.nqn}
          '';
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "5min";
          };
        }
      ];
      "vm@slop-cannon" = {
        requires = [ "slop-cannon-disk.service" ];
        bindsTo = [ "slop-cannon-disk.service" ];
        after = [ "slop-cannon-disk.service" ];
        # Coding agents; keep storage and the router responsive
        serviceConfig.CPUWeight = 20;
      };
    };

    my = {
      vms = {
        instances = {
          cellar = {
            uuid = "b126d135-9fc1-415a-b675-aaf727bf2f38";
            cpu = "host,topoext";
            smp = {
              cpus = 8;
              threads = 2;
            };
            memory = 16384;
            cleanShutdown.timeout = 120;
            drives = [
              (mkMerge [ (vm.disk "cellar" "esp") { frontendOpts.bootindex = 0; } ])
              (vm.disk "cellar" "nix")
              (vm.disk "cellar" "persist")
            ];
            hostDevices = {
              cellar-hi = {
                index = 0;
                hostBDF = "44:00.1";
              };
              nvme0 = {
                index = 1;
                hostBDF = "41:00.0";
              };
              nvme1 = {
                index = 2;
                hostBDF = "42:00.0";
              };
              nvme2 = {
                index = 3;
                hostBDF = "43:00.0";
              };
            };
            qemuFlags = [
              "machine kernel-irqchip=split"
              "device intel-iommu,caching-mode=on,device-iotlb=on,intremap=on"
            ];
          };

          river = {
            uuid = "12b52d80-ccb6-418d-9b2e-2be34bff3cd9";
            cpu = "host,topoext";
            smp = {
              cpus = 3;
              threads = 2;
            };
            memory = 4096;
            cleanShutdown.timeout = 60;
            networks = {
              lan-jim = {
                ifname = "river-jim-tap";
                bridge = null;
                tapFD = 100;
                # Real hardware MAC
                mac = "e0:d5:5e:68:0c:6e";
                waitOnline = false;
              };
            };
            drives = [
              installerDisk
              (mkMerge [ (vm.disk "river" "esp") { frontendOpts.bootindex = 0; } ])
            ];
            hostDevices = {
              river-rdma = {
                index = 0;
                hostBDF = "44:00.2";
              };
              river-dave = {
                index = 1;
                hostBDF = "44:00.5";
              };
            };
          };

          sfh = {
            uuid = "82ec149d-577c-421a-93e2-a9307c756cd8";
            cpu = "host,topoext";
            smp = {
              cpus = 8;
              threads = 2;
            };
            memory = 32768;
            cleanShutdown.timeout = 120;
            networks = {
              netboot = {
                bridge = "lan-lo";
                ifname = "sfh-lo-tap";
                waitOnline = "carrier";
                mac = "52:54:00:a5:7e:93";
                extraOptions.bootindex = 1;
              };
              core = {
                bridge = "lan-core";
                ifname = "sfh-core-tap";
                waitOnline = "carrier";
                mac = "52:54:00:72:67:51";
              };
            };
            drives = [
              (vm.lvmDisk' "hdds" "frigate")
            ];
            hostDevices = {
              sfh-hi = {
                index = 0;
                hostBDF = "44:00.3";
              };
              sfh-ctrs = {
                index = 1;
                hostBDF = "44:00.4";
              };
            };
            qemuFlags = [
              "device qemu-xhci,id=xhci"
              # Front-right port?
              "device usb-host,hostbus=1,hostport=4"
              # Front-left port
              "device usb-host,hostbus=1,hostport=3"
            ];
          };

          slop-cannon = {
            uuid = "9de7dc84-7506-445f-8e37-37c4cc6d8ed5";
            cpu = "host,topoext";
            # Overcommitted so agents can burst; `vm@slop-cannon` has a low CPU weight
            smp = {
              cpus = 16;
              threads = 2;
            };
            memory = 24576;
            cleanShutdown.timeout = 120;
            drives = [
              installerDisk
              (mkMerge [ (vm.blockDisk "disk" slopDisk.device) { frontendOpts.bootindex = 0; } ])
            ];
            hostDevices = {
              slop-cannon-ut = {
                index = 0;
                hostBDF = "44:00.6";
              };
            };
          };
        };
      };
    };
  };
}
