{
  imports = [
    ./estuary
    ./shill
  ];

  nixos.systems.colony.configuration = { lib, pkgs, config, systems, ... }:
  let
    inherit (lib) mkMerge;

    wanBDF =
      if config.my.build.isDevVM then "00:02.0" else "01:00.0";

    vmLVM = vm: lv: {
      "${lv}" = {
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
    };
  in
  {
    systemd = {
      services."vm@estuary" = {
        # Depend the interface, networkd wait-online would deadlock...
        requires = [ "sys-subsystem-net-devices-base.device" ];
        preStart = ''
          count=0
          while ! ${pkgs.iproute2}/bin/ip link show dev base > /dev/null 2>&1; do
              count=$((count+1))
              if [ $count -ge 5 ]; then
                echo "Timed out waiting for bridge interface"
              fi
              sleep 0.5
          done
        '';
      };
    };

    my = {
      vms = {
        instances = {
          estuary = {
            uuid = "59f51efb-7e6d-477b-a263-ed9620dbc87b";
            networks.base.mac = "52:54:00:ab:f1:52";
            drives = {
              # TODO: Split into separate LVs
              disk = {
                backend = {
                  driver = "host_device";
                  filename = "/dev/ssds/vm-estuary";
                  # It appears this needs to be set on the backend _and_ the format
                  discard = "unmap";
                };
                format = {
                  driver = "raw";
                  discard = "unmap";
                };
                frontend = "virtio-blk";
              };
            };
            hostDevices."${wanBDF}" = { };
          };
          shill = {
            uuid = "e34569ec-d24e-446b-aca8-a3b27abc1f9b";
            networks.vms.mac = "52:54:00:85:b3:b1";
            drives = mkMerge [
              (vmLVM "shill" "esp")
              (vmLVM "shill" "nix")
              (vmLVM "shill" "persist")
              {
                installer = {
                  backend = {
                    driver = "file";
                    filename = "${systems.installer.configuration.config.my.buildAs.iso}/iso/nixos.iso";
                    read-only = "on";
                  };
                  format.driver = "raw";
                  frontend = "ide-cd";
                  frontendOpts = {
                    bootindex = 1;
                  };
                };
                esp.frontendOpts.bootindex = 0;
              }
            ];
          };
        };
      };
    };
  };
}
