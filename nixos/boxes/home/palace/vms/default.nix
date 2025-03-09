{
  imports = [
    ./cellar
    ./river.nix
    ./sfh
  ];

  nixos.systems.palace.configuration = { lib, pkgs, config, systems, allAssignments, ... }:
  let
    inherit (lib) mkMerge;
    inherit (lib.my) vm;
    inherit (lib.my.c) networkd;

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
  in
  {
    systemd.network = {
      netdevs = {
        "25-vm-et1g0" = {
           netdevConfig = {
             Name = "vm-et1g0";
             Kind = "macvtap";
           };
           # TODO: Upstream this missing section
           extraConfig = ''
             [MACVTAP]
             Mode=passthru
           '';
        };
      };
      networks = {
        "75-et1g0" = {
          matchConfig.Name = "et1g0";
          linkConfig.RequiredForOnline = "no";
          networkConfig = {
            MACVTAP = "vm-et1g0";
          } // networkd.noL3;
        };
        "75-vm-et1g0" = {
          matchConfig.Name = "vm-et1g0";
          linkConfig.RequiredForOnline = "no";
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
        vtapUnit = "sys-subsystem-net-devices-vm\\x2det1g0.device";
      in
      mkMerge [
        (awaitVM "cellar")
        {
          requires = [ vtapUnit ];
          after = [ vtapUnit ];
        }
      ];
      "vm@sfh" = (awaitVM "river");
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
              et100g0vf0 = {
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
              et1g0 = {
                ifname = "vm-et1g0";
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
              et100g0vf1 = {
                index = 0;
                hostBDF = "44:00.2";
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
            networks.netboot = {
              bridge = "lan-lo";
              waitOnline = "carrier";
              mac = "52:54:00:a5:7e:93";
              extraOptions.bootindex = 1;
            };
            hostDevices = {
              et100g0vf2 = {
                index = 0;
                hostBDF = "44:00.3";
              };
              et100g0vf3 = {
                index = 1;
                hostBDF = "44:00.4";
              };
            };
            qemuFlags = [
              "device qemu-xhci,id=xhci"
              # Front-right port?
              "device usb-host,hostbus=1,hostport=4"
            ];
          };
        };
      };
    };
  };
}
