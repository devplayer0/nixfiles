{
  imports = [
    ./estuary
    ./shill
    ./whale2
    ./git
  ];

  nixos.systems.colony.configuration = { lib, pkgs, config, systems, ... }:
  let
    inherit (lib) mkIf mkMerge optionals;
    inherit (lib.my) vm;

    installerDisk = {
      name = "installer";
      backend = {
        driver = "file";
        #filename = "${systems.installer.configuration.config.my.buildAs.iso}/iso/nixos-installer-devplayer0.iso";
        filename = "/persist/home/dev/nixos-installer-devplayer0-b4d0d9a.iso";
        #filename = "/persist/home/dev/debian-12.1.0-amd64-netinst.iso";
        # filename = "/persist/home/dev/ubuntu-22.04.3-live-server-amd64.iso";
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
    # Kernel Same-Page Merging to attempt memory usage reduction
    hardware.ksm.enable = false;

    systemd = {
      network = {
        links = {
          #"10-wan10g" = {
          #  matchConfig.Path = "pci-0000:2d:00.0";
          #  linkConfig.Name = "wan10g";
          #};
        };
        netdevs = {
          #"25-vm-wan10g" = {
          #  netdevConfig = {
          #    Name = "vm-wan10g";
          #    Kind = "macvtap";
          #  };
          #  # TODO: Upstream this missing section
          #  extraConfig = ''
          #    [MACVTAP]
          #    Mode=passthru
          #  '';
          #};
        };
        networks = {
          #"75-wan10g" = {
          #  matchConfig.Name = "wan10g";
          #  networkConfig.MACVTAP = "vm-wan10g";
          #};
          #"75-vm-wan10g" = {
          #  matchConfig.Name = "vm-wan10g";
          #  linkConfig.RequiredForOnline = "no";
          #};
        };
      };

      services = {
        #"vm@estuary" =
        #let
        #  vtapUnit = "sys-subsystem-net-devices-vm\\x2dwan10g.device";
        #in
        #{
        #  requires = [ vtapUnit ];
        #  after = [ vtapUnit ];
        #};
      };
    };

    my = {
      vms = {
        instances = {
          estuary = {
            uuid = "27796a09-c013-4031-9595-44791d6126b9";
            cpu = "host,topoext";
            smp = {
              cpus = 2;
              threads = 2;
            };
            memory = 3072;
            networks = {
              # Mellanox ConnectX-2 hackery
              #wan = {
              #  ifname = "vm-wan10g";
              #  bridge = null;
              #  tapFD = 100;
              #  # Real hardware MAC
              #  mac = "00:02:c9:56:24:6e";
              #  waitOnline = false;
              #};
              base = {
                waitOnline = "carrier";
                mac = "52:54:00:15:1a:53";
              };
            };
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (mkMerge [ (vm.disk "estuary" "esp") { frontendOpts.bootindex = 0; } ])
              (vm.disk "estuary" "nix")
              (vm.disk "estuary" "persist")
            ]);
            hostDevices = {
              net-wan0 = {
                index = 0;
                hostBDF = if config.my.build.isDevVM then "00:02.0" else "27:00.0";
              };
            };
          };

          shill = {
            uuid = "fc02d8c8-6f60-4b69-838a-e7aed6ee7617";
            cpu = "host,topoext";
            smp = {
              cpus = 12;
              threads = 2;
            };
            memory = 40960;
            networks.vms.mac = "52:54:00:27:3d:5c";
            cleanShutdown.timeout = 120;
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (mkMerge [ (vm.disk "shill" "esp") { frontendOpts.bootindex = 0; } ])
              (vm.disk "shill" "nix")
              (vm.disk "shill" "persist")

              (vm.lvmDisk "media")
              (vm.lvmDisk "minio")
              (vm.lvmDisk "nix-atticd")
              (vm.lvmDisk "jam")
            ]);
          };

          whale2 = {
            uuid = "6d31b672-1f32-4e2b-a39f-78a5b5e949a0";
            cpu = "host,topoext";
            smp = {
              cpus = 8;
              threads = 2;
            };
            memory = 16384;
            networks.vms.mac = "52:54:00:d5:d9:c6";
            cleanShutdown.timeout = 120;
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (mkMerge [ (vm.disk "whale2" "esp") { frontendOpts.bootindex = 0; } ])
              (vm.disk "whale2" "nix")
              (vm.disk "whale2" "persist")

              (vm.lvmDisk "oci")
            ]);
          };

          git = {
            uuid = "c0659fdc-3356-4717-a6a1-5f289ef03c4a";
            cpu = "host,topoext";
            smp = {
              cpus = 12;
              threads = 2;
            };
            memory = 40960;
            networks.vms.mac = "52:54:00:75:78:a8";
            cleanShutdown.timeout = 120;
            drives = [
              (mkMerge [ (vm.disk "git" "esp") { frontendOpts.bootindex = 0; } ])
              (vm.disk "git" "nix")
              (vm.disk "git" "persist")
              (vm.disk "git" "oci")

              (vm.lvmDisk "git")
              (vm.lvmDisk "gitea-actions-cache")
            ];
          };

          mail = {
            uuid = "fd95fe0f-c204-4dd5-b16f-2b808e14a43a";
            cpu = "host,topoext";
            smp = {
              cpus = 3;
              threads = 2;
            };
            memory = 6144;
            networks.public = {
              bridge = null;
              mac = "52:54:00:a8:d1:03";
            };
            cleanShutdown.timeout = 120;
            drives = [
              (mkMerge [ (vm.disk "mail" "root") { frontendOpts.bootindex = 0; } ])
              (vm.disk "mail" "data")
            ];
          };

          darts = {
            uuid = "ee3882a9-5616-4fcb-83d7-89eb41a84d28";
            cpu = "host,topoext";
            smp = {
              cpus = 4;
              threads = 2;
            };
            memory = 16384;
            networks.public = {
              bridge = null;
              mac = "52:54:00:a8:29:cd";
            };
            cleanShutdown.timeout = 120;
            drives = [
              (mkMerge [ (vm.disk "darts" "root") { frontendOpts.bootindex = 0; } ])
              (vm.lvmDisk' "media" "darts-media")
              (vm.lvmDisk' "ext" "darts-ext")
            ];
          };
        };
      };
    };
  };
}
