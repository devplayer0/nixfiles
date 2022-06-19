{
  imports = [
    ./estuary
    ./shill
  ];

  nixos.systems.colony.configuration = { lib, pkgs, config, systems, ... }:
  let
    inherit (builtins) listToAttrs;
    inherit (lib) mkIf mkMerge optionals;

    wanBDF =
      if config.my.build.isDevVM then "00:02.0" else "27:00.0";

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
            networks.base = {
              waitOnline = "no-carrier";
              mac = "52:54:00:15:1a:53";
            };
            drives = [ ] ++ (optionals (!config.my.build.isDevVM) [
              (vmLVM "estuary" "esp")
              (vmLVM "estuary" "nix")
              (vmLVM "estuary" "persist")
            ]);
            hostDevices."${wanBDF}" = { };
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
