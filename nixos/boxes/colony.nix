{
  nixos.systems.colony = {
    system = "x86_64-linux";
    nixpkgs = "mine";
    home-manager = "unstable";

    assignments.internal = {
      name = "colony";
      altNames = [ "vm" ];
      ipv4.address = "10.100.0.2";
      ipv6.address = "2a0e:97c0:4d1:0::2";
    };

    configuration = { lib, pkgs, modulesPath, config, systems, assignments, ... }:
      let
        inherit (lib) mkIf mapAttrs;
        inherit (lib.my) networkdAssignment;

        wanBDF =
          if config.my.build.isDevVM then "00:02.0" else "01:00.0";
      in
      {
        imports = [ "${modulesPath}/profiles/qemu-guest.nix" ];

        networking.domain = "nl1.int.nul.ie";

        boot.kernelParams = [ "intel_iommu=on" ];
        boot.loader.systemd-boot.configurationLimit = 20;
        fileSystems = {
          "/boot" = {
            device = "/dev/disk/by-label/ESP";
            fsType = "vfat";
          };
          "/nix" = {
            device = "/dev/ssds/colony-nix";
            fsType = "ext4";
          };
          "/persist" = {
            device = "/dev/ssds/colony-persist";
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

        environment.systemPackages = with pkgs; [
          pciutils
        ];

        systemd = {
          network = {
            links = {
              "10-base-ext" = {
                matchConfig.MACAddress = "52:54:00:81:bd:a1";
                linkConfig.Name = "base-ext";
              };
            };
            netdevs."25-base".netdevConfig = {
              Name = "base";
              Kind = "bridge";
            };
            networks = {
              "80-base" = networkdAssignment "base" assignments.internal;
              "80-base-ext" = {
                matchConfig.Name = "base-ext";
                networkConfig.Bridge = "base";
              };
              "80-vm-tap" = {
                matchConfig = {
                  # Don't think we have control over the name of the TAP from qemu-bridge-helper (or how to easily pick
                  # which interface is which)
                  Name = "tap*";
                  Driver = "tun";
                };
                networkConfig = {
                  KeepMaster = true;
                  LLDP = true;
                  EmitLLDP = "customer-bridge";
                };
              };
            };
          };

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

        #environment.etc."udev/udev.conf".text = "udev_log=debug";
        #systemd.services.systemd-networkd.environment.SYSTEMD_LOG_LEVEL = "debug";
        virtualisation = {
          cores = 8;
          memorySize = 8192;
          qemu.options = [
            "-machine q35"
            "-accel kvm,kernel-irqchip=split"
            "-device intel-iommu,intremap=on,caching-mode=on"
          ];
        };

        my = {
          #deploy.generate.system.mode = "boot";
          secrets = {
            key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKp5WDdDr/1NS3SJIDOKwcCNZDFOxqPAD7cbZWAP7EkX";
            files."test.txt" = {};
          };

          server.enable = true;

          firewall = {
            trustedInterfaces = [ "base" ];
          };

          #containers = {
          #  instances.vaultwarden = {
          #    networking.bridge = "virtual";
          #  };
          #};
          vms = {
            instances.estuary = {
              uuid = "59f51efb-7e6d-477b-a263-ed9620dbc87b";
              networks.base.mac = "52:54:00:ab:f1:52";
              drives = {
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
                  frontendOpts = {
                    bootindex = 0;
                  };
                };
              };
              hostDevices."${wanBDF}" = { };
            };
          };
        };
      };
  };
}
