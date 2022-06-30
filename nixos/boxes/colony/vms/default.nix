{
  imports = [
    ./estuary
    ./shill
  ];

  nixos.systems.colony.configuration = { lib, pkgs, config, systems, ... }:
  let
    inherit (builtins) listToAttrs;
    inherit (lib) mkIf mkMerge optionals;

    vmLVM = vm: lv: {
      name = lv;
      backend = {
        driver = "host_device";
        filename = "/dev/ssds/vm-${vm}-${lv}";
        # It appears this needs to be set on the backend _and_ the format
        discard = "unmap";
      };
      format = {
        driver = "raw";
        discard = "unmap";
      };
      frontend = "virtio-blk";
    };

    installerDisk = {
      name = "installer";
      backend = {
        driver = "file";
        filename = "${systems.installer.configuration.config.my.buildAs.iso}/iso/nixos-installer-devplayer0.iso";
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
    systemd = {
      network = {
        links = {
          "10-wan10g" = {
            matchConfig.Path = "pci-0000:2d:00.0";
            linkConfig.Name = "wan10g";
          };
        };
        netdevs = {
          "25-vm-wan10g" = {
            netdevConfig = {
              Name = "vm-wan10g";
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
          "75-wan10g" = {
            matchConfig.Name = "wan10g";
            networkConfig.MACVTAP = "vm-wan10g";
          };
          "75-vm-wan10g" = {
            matchConfig.Name = "vm-wan10g";
            linkConfig.RequiredForOnline = "carrier";
          };
        };
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
              wan = {
                ifname = "vm-wan10g";
                bridge = null;
                tapFD = 100;
                # Real hardware MAC
                mac = "00:02:c9:56:24:6e";
              };
              base = {
                waitOnline = "carrier";
                mac = "52:54:00:15:1a:53";
              };
            };
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (mkMerge [ (vmLVM "estuary" "esp") { frontendOpts.bootindex = 0; } ])
              (vmLVM "estuary" "nix")
              (vmLVM "estuary" "persist")
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
            memory = 65536;
            networks.vms.mac = "52:54:00:27:3d:5c";
            cleanShutdown.timeout = 120;
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (vmLVM "shill" "esp")
              (vmLVM "shill" "nix")
              (vmLVM "shill" "persist")
              {
                name = "media";
                backend = {
                  driver = "host_device";
                  filename = "/dev/hdds/media";
                  discard = "unmap";
                };
                format = {
                  driver = "raw";
                  discard = "unmap";
                };
                frontend = "virtio-blk";
              }
            ]);
          };
        };
      };
    };
  };
}
