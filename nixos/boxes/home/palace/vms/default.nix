{
  imports = [
    ./cellar
  ];

  nixos.systems.palace.configuration = { lib, pkgs, config, systems, ... }:
  let
    inherit (lib) mkMerge;
    inherit (lib.my) vm;

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
    systemd.services = {
      "vm@cellar" = {
        serviceConfig = {
          CPUAffinity = "numa";
          NUMAPolicy = "bind";
          NUMAMask = "1";
        };
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
            memory = 32768;
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
          };
        };
      };
    };
  };
}
